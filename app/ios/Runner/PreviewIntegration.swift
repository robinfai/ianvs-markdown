import Flutter
import UIKit
import UniformTypeIdentifiers

final class PreviewIntegration: NSObject, UIDocumentPickerDelegate {
  static let shared = PreviewIntegration()
  private let queue = DispatchQueue(label: "work.ianvs.linefold.imports", qos: .userInitiated)
  private let localDocuments = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
  private var folderResult: FlutterResult?
  private var scopedFolders: [URL] = []
  private var channel: FlutterMethodChannel?
  private var pendingPaths: [String] = []
  private var pendingErrors: [String] = []
  private var ready = false
  private var importing: Set<URL> = []

  func attach(to messenger: FlutterBinaryMessenger) {
    CloudWorkspace.shared.attach(to: messenger)
    let channel = FlutterMethodChannel(name: "work.ianvs.linefold/preview", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "takePendingFiles":
        self.ready = true
        let paths = self.pendingPaths
        let errors = self.pendingErrors
        self.pendingPaths.removeAll()
        self.pendingErrors.removeAll()
        result(["paths": paths, "errors": errors])
      case "chooseFiles": self.chooseFiles(result: result)
      case "defaultWorkspace":
        self.queue.async {
          let workspace = self.defaultWorkspace()
          DispatchQueue.main.async { result(workspace) }
        }
      case "chooseWorkspace": self.chooseFiles(result: result, folder: true)
      case "openExternal":
        guard let value = call.arguments as? String, let url = URL(string: value),
              ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") else {
          result(FlutterError(code: "invalid_link", message: "无法打开这个链接。", details: nil))
          return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
          result(opened ? nil : FlutterError(code: "open_failed", message: "无法打开这个链接。", details: nil))
        }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  @discardableResult
  func receive(_ urls: [URL]) -> Bool {
    let files = urls.filter(\.isFileURL)
    for url in files where !importing.contains(url) {
      importing.insert(url)
      queue.async {
        let outcome = Result {
          let workspace = self.defaultWorkspace()
          let directory = URL(fileURLWithPath: workspace["path"] as! String)
          return try MarkdownImporter(documentsDirectory: directory).importFile(at: url)
        }
        DispatchQueue.main.async {
          self.importing.remove(url)
          switch outcome {
          case .success(let imported): self.pendingPaths.append(imported.path)
          case .failure(let error):
            self.pendingErrors.append("\(url.lastPathComponent)：\(error.localizedDescription)")
          }
          if self.ready { self.channel?.invokeMethod("filesAvailable", arguments: nil) }
        }
      }
    }
    return !files.isEmpty
  }

  private func defaultWorkspace() -> [String: Any] {
    do {
      let root = try CloudWorkspace.shared.defaultDirectory()
      // Preserve old imports in place. Copy stable UUID directories once so an
      // upgrade never overwrites an edited cloud document or duplicates imports.
      let previous = localDocuments.appendingPathComponent("Imports", isDirectory: true)
      let target = root.appendingPathComponent("Imports", isDirectory: true)
      let migrationKey = "cloudMigratedImportIDs"
      var migrated = Set(UserDefaults.standard.stringArray(forKey: migrationKey) ?? [])
      var migrationFailed = false
      if FileManager.default.fileExists(atPath: previous.path) {
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for directory in try FileManager.default.contentsOfDirectory(at: previous, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey]) {
          let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
          guard values.isDirectory == true, values.isSymbolicLink != true,
                !migrated.contains(directory.lastPathComponent) else { continue }
          let destination = target.appendingPathComponent(directory.lastPathComponent)
          do {
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
              guard CloudWorkspace.extensions.contains(file.pathExtension.lowercased()),
                    try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { continue }
              let copy = destination.appendingPathComponent(file.lastPathComponent)
              let stub = destination.appendingPathComponent(".\(file.lastPathComponent).icloud")
              if !FileManager.default.fileExists(atPath: copy.path) && !FileManager.default.fileExists(atPath: stub.path) {
                try CloudWorkspace.write(copy, contents: CloudWorkspace.read(file, maximumBytes: MarkdownImporter.maximumBytes))
              }
            }
            migrated.insert(directory.lastPathComponent)
            // Keep the local backup, but never resurrect an import later deleted
            // from iCloud. Interrupted migrations resume per file on next launch.
            UserDefaults.standard.set(Array(migrated), forKey: migrationKey)
          } catch {
            migrationFailed = true
          }
        }
      }
      var workspace: [String: Any] = ["path": root.path, "isCloud": true, "name": "iCloud · Linefold"]
      if migrationFailed { workspace["notice"] = "部分本机文档未能迁入 iCloud，原副本已保留。请稍后重试。" }
      return workspace
    } catch {
      return ["path": localDocuments.path, "isCloud": false, "name": "此 iPhone · Linefold",
              "notice": error as? WorkspaceError == .notConfigured
                ? "iCloud 自动同步尚未启用，文档保存在此 iPhone。仍可手动打开 iCloud Drive 文件夹。"
                : "iCloud 暂不可用，文档暂存于此 iPhone。恢复 iCloud 后将自动迁入。"]
    }
  }

  private func chooseFiles(result: @escaping FlutterResult, folder: Bool = false) {
    guard let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first(where: { $0.activationState == .foregroundActive }),
      let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
      result(FlutterError(code: "no_window", message: "暂时无法打开文件选择器。", details: nil))
      return
    }
    var presenter = root
    while let presented = presenter.presentedViewController { presenter = presented }
    guard !(presenter is UIDocumentPickerViewController) else {
      result(FlutterError(code: "picker_busy", message: "请先关闭当前文件选择器。", details: nil))
      return
    }
    let types = folder ? [UTType.folder] : MarkdownImporter.extensions.compactMap { UTType(filenameExtension: $0) }
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: !folder)
    picker.delegate = self
    picker.allowsMultipleSelection = !folder
    if folder { folderResult = result }
    presenter.present(picker, animated: true)
    if !folder { result(nil) }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    if let result = folderResult {
      folderResult = nil
      guard let url = urls.first, url.startAccessingSecurityScopedResource() else {
        result(FlutterError(code: "folder_unavailable", message: "无法访问文件夹，请重新选择。", details: nil))
        return
      }
      // Retain access for open reader routes during this session. On next launch
      // the app always returns to its own iCloud folder, without auto-restoring grants.
      scopedFolders.append(url)
      result(["path": url.path, "isCloud": false, "name": url.lastPathComponent])
    } else {
      receive(urls)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    folderResult?(nil)
    folderResult = nil
  }
}
