import Flutter
import UIKit
import UniformTypeIdentifiers

final class PreviewIntegration: NSObject, UIDocumentPickerDelegate {
  static let shared = PreviewIntegration()
  private let queue = DispatchQueue(label: "work.ianvs.linefold.imports", qos: .userInitiated)
  private let localDocuments = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
  private var folderResult: FlutterResult?
  private var selectingOperationFolder = false
  private var scopedFolders: [URL] = []
  private var exportChannel: FlutterMethodChannel?
  private var channel: FlutterMethodChannel?
  private var pendingPaths: [String] = []
  private var pendingErrors: [String] = []
  private var ready = false
  private var importing: Set<URL> = []

  func attach(to messenger: FlutterBinaryMessenger) {
    CloudWorkspace.shared.attach(to: messenger)
    let exports = FlutterMethodChannel(name: "work.ianvs.linefold/document_export", binaryMessenger: messenger)
    exportChannel = exports
    exports.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      if call.method == "cancel" { result(true); return }
      guard ["html", "markdown", "pdf", "bundle"].contains(call.method),
            let arguments = call.arguments as? [String: Any],
            let operation = arguments["operationId"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      exports.invokeMethod("approveCommit", arguments: ["operationId": operation]) { approved in
        guard approved as? Bool == true else { result(false); return }
        self.shareExport(call.method, arguments: arguments, result: result)
      }
    }
    let channel = FlutterMethodChannel(name: "work.ianvs.linefold/preview", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      #if DEBUG && targetEnvironment(simulator)
      case "prepareSimulatorAudit":
        self.queue.async {
          do {
            let fixture = try SimulatorAuditFixture.prepare(self.localDocuments)
            DispatchQueue.main.async { result(fixture) }
          } catch {
            DispatchQueue.main.async { result(FlutterError(code: "fixture_failed", message: error.localizedDescription, details: nil)) }
          }
        }
      #endif
      case "takePendingFiles":
        self.ready = true
        let paths = self.pendingPaths
        let errors = self.pendingErrors
        self.pendingPaths.removeAll()
        self.pendingErrors.removeAll()
        result(["paths": paths, "errors": errors])
      case "clipboardImage":
        if let bytes = UIPasteboard.general.image?.pngData(), bytes.count <= 20 * 1024 * 1024 {
          result(FlutterStandardTypedData(bytes: bytes))
        } else { result(nil) }
      case "chooseFiles": self.chooseFiles(result: result)
      case "defaultWorkspace":
        self.queue.async {
          do {
            let workspace = try self.defaultWorkspace()
            DispatchQueue.main.async { result(workspace) }
          } catch {
            DispatchQueue.main.async {
              result(FlutterError(code: error is WorkspaceWriteAuthorityError ? "workspace_busy" : "workspace_unavailable",
                                  message: error.localizedDescription, details: nil))
            }
          }
        }
      case "chooseWorkspace":
        self.chooseFiles(result: result, folder: true)
      case "chooseOperationFolder":
        self.chooseFiles(result: result, folder: true, operationFolder: true)
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

  private func shareExport(_ kind: String, arguments: [String: Any], result: @escaping FlutterResult) {
    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
          var presenter = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
      result(FlutterError(code: "export_unavailable", message: "无法打开分享面板。", details: nil))
      return
    }
    while let presented = presenter.presentedViewController { presenter = presented }
    do {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let rawTitle = (arguments["title"] as? String ?? "Document") as NSString
      let title = (rawTitle.lastPathComponent as NSString).deletingPathExtension
      let suffix = ["html": "html", "markdown": "md", "pdf": "pdf", "bundle": "zip"][kind]!
      let url = directory.appendingPathComponent(title.isEmpty ? "Document" : title).appendingPathExtension(suffix)
      let data: Data
      if kind == "bundle", let bytes = arguments["bytes"] as? FlutterStandardTypedData {
        data = bytes.data
      } else if let content = arguments["content"] as? String {
        if kind == "pdf" {
          let renderer = UIPrintPageRenderer()
          renderer.addPrintFormatter(UIMarkupTextPrintFormatter(markupText: content), startingAtPageAt: 0)
          let paper = CGRect(x: 0, y: 0, width: 595, height: 842)
          renderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
          renderer.setValue(NSValue(cgRect: paper.insetBy(dx: 36, dy: 36)), forKey: "printableRect")
          data = UIGraphicsPDFRenderer(bounds: paper).pdfData { context in
            renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
            for page in 0..<renderer.numberOfPages {
              context.beginPage()
              renderer.drawPage(at: page, in: paper)
            }
          }
        } else {
          data = Data(content.utf8)
        }
      } else {
        try? FileManager.default.removeItem(at: directory)
        result(FlutterError(code: "export_invalid", message: "导出内容不可用。", details: nil))
        return
      }
      try data.write(to: url, options: .atomic)
      let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
      sheet.popoverPresentationController?.sourceView = presenter.view
      sheet.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
      sheet.completionWithItemsHandler = { _, completed, _, error in
        try? FileManager.default.removeItem(at: directory)
        if let error {
          result(FlutterError(code: "export_failed", message: error.localizedDescription, details: nil))
        } else { result(completed) }
      }
      presenter.present(sheet, animated: true)
    } catch {
      result(FlutterError(code: "export_failed", message: error.localizedDescription, details: nil))
    }
  }

  @discardableResult
  func receive(_ urls: [URL]) -> Bool {
    let files = urls.filter(\.isFileURL)
    for url in files where !importing.contains(url) {
      importing.insert(url)
      queue.async {
        let outcome = Result {
          let workspace = try self.defaultWorkspace(activate: false)
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

  private func defaultWorkspace(activate: Bool = true) throws -> [String: Any] {
    var workspace = defaultWorkspaceLocation()
    if activate {
      let root = URL(fileURLWithPath: workspace["path"] as! String)
      for (key, value) in try CloudWorkspace.shared.previewWriteAuthority.activate(root) {
        workspace[key] = value
      }
    }
    return workspace
  }

  // Importing a shared copy does not switch the selected root or its write
  // capability. Dart explicitly selects the default workspace before opening it.
  private func defaultWorkspaceLocation() -> [String: Any] {
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

  private func chooseFiles(result: @escaping FlutterResult, folder: Bool = false, operationFolder: Bool = false) {
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
    if folder { folderResult = result; selectingOperationFolder = operationFolder }
    presenter.present(picker, animated: true)
    if !folder { result(nil) }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    if let result = folderResult {
      folderResult = nil
      let operationFolder = selectingOperationFolder
      selectingOperationFolder = false
      guard let url = urls.first else {
        result(FlutterError(code: "folder_unavailable", message: "无法访问文件夹，请重新选择。", details: nil))
        return
      }
      queue.async {
        guard url.startAccessingSecurityScopedResource() else {
          DispatchQueue.main.async {
            result(FlutterError(code: "folder_unavailable", message: "无法访问文件夹，请重新选择。", details: nil))
          }
          return
        }
        do {
          let access = try operationFolder ? CloudWorkspace.shared.operationWriteGrants.activate(url) : CloudWorkspace.shared.previewWriteAuthority.activate(url)
          DispatchQueue.main.async {
            // Retain old scopes for readers, never as write authorization. Each
            // explicit selection gets a fresh nonpersistent native capability.
            self.scopedFolders.append(url)
            result(["path": access["path"]!, "workspaceToken": access["workspaceToken"]!,
                    "isCloud": false, "name": url.lastPathComponent])
          }
        } catch {
          url.stopAccessingSecurityScopedResource()
          DispatchQueue.main.async {
            result(FlutterError(code: error is WorkspaceWriteAuthorityError ? "workspace_busy" : "folder_unavailable",
                                message: error.localizedDescription, details: nil))
          }
        }
      }
    } else {
      receive(urls)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    folderResult?(nil)
    folderResult = nil
  }
}
