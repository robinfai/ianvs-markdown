import Cocoa
import ServiceManagement
import UniformTypeIdentifiers

protocol MarkdownApplicationWorkspace {
  func defaultApplication() -> URL?
  func setDefaultApplication(_ application: URL, completion: @escaping (Error?) -> Void)
  func applicationExists(_ application: URL) -> Bool
  func chooseApplication(completion: @escaping (URL?) -> Void)
}

final class MacOSMarkdownApplicationWorkspace: MarkdownApplicationWorkspace {
  // Use the established Markdown UTI on macOS 12+, including systems that
  // predate the UTType.markdown convenience constant.
  private let markdownType = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .utf8PlainText)

  func defaultApplication() -> URL? {
    NSWorkspace.shared.urlForApplication(toOpen: markdownType)
  }

  func setDefaultApplication(_ application: URL, completion: @escaping (Error?) -> Void) {
    NSWorkspace.shared.setDefaultApplication(at: application, toOpen: markdownType) { error in
      DispatchQueue.main.async { completion(error) }
    }
  }

  func applicationExists(_ application: URL) -> Bool {
    FileManager.default.fileExists(atPath: application.path)
  }

  func chooseApplication(completion: @escaping (URL?) -> Void) {
    let panel = NSOpenPanel()
    panel.title = "Default Markdown Application"
    panel.message = "Choose the application that should open .md files."
    panel.prompt = "Choose"
    panel.allowedContentTypes = [.applicationBundle]
    panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.begin { response in
      completion(response == .OK ? panel.url : nil)
    }
  }
}

/// Stores the user's intention independently from the live Launch Services state.
/// Merely loading preferences must never change another application's association.
final class MarkdownFileAssociation {
  private let defaults: UserDefaults
  private let workspace: MarkdownApplicationWorkspace
  private let applicationURL: URL
  private let preferenceKey = "markdownAssociation.preferLinefold"
  private let previousApplicationKey = "markdownAssociation.previousApplicationURL"
  private var changing = false

  init(
    defaults: UserDefaults = .standard,
    workspace: MarkdownApplicationWorkspace = MacOSMarkdownApplicationWorkspace(),
    applicationURL: URL = Bundle.main.bundleURL
  ) {
    self.defaults = defaults
    self.workspace = workspace
    self.applicationURL = applicationURL
  }

  func state() -> [String: Any] {
    let current = workspace.defaultApplication()
    var value: [String: Any] = ["isDefault": isLinefold(current)]
    if let preference = defaults.object(forKey: preferenceKey) as? Bool {
      value["preferLinefold"] = preference
    }
    if let current {
      value["currentApplicationName"] = applicationName(current)
    }
    if let previous = previousApplication() {
      value["previousApplicationName"] = applicationName(previous)
    }
    return value
  }

  func setPreference(_ preferLinefold: Bool, completion: @escaping (Error?) -> Void) {
    guard !changing else {
      completion(AssociationError("A default-application change is already in progress."))
      return
    }
    // Save both acceptance and refusal before macOS potentially asks for consent.
    // Cancellation or an OS error must not cause repeated startup prompts.
    defaults.set(preferLinefold, forKey: preferenceKey)
    let current = workspace.defaultApplication()
    if preferLinefold {
      guard !isLinefold(current) else { completion(nil); return }
      if let current {
        defaults.set(current.absoluteString, forKey: previousApplicationKey)
      } else {
        defaults.removeObject(forKey: previousApplicationKey)
      }
      apply(applicationURL, completion: completion)
    } else {
      // Respect a newer choice made in Finder or another application.
      guard isLinefold(current) else { completion(nil); return }
      if let previous = previousApplication() {
        apply(previous, completion: completion)
      } else {
        changing = true
        workspace.chooseApplication { [weak self] application in
          guard let self else { return }
          self.changing = false
          guard let application else {
            completion(AssociationError(
              "Your preference was saved. Linefold is still the default because no replacement application was selected."))
            return
          }
          guard !self.isLinefold(application) else {
            completion(AssociationError("Choose another application to stop using Linefold by default."))
            return
          }
          self.apply(application, completion: completion)
        }
      }
    }
  }

  private func apply(_ target: URL, completion: @escaping (Error?) -> Void) {
    changing = true
    workspace.setDefaultApplication(target) { [weak self] error in
      guard let self else { return }
      self.changing = false
      guard error == nil, self.sameApplication(self.workspace.defaultApplication(), target) else {
        completion(AssociationError(
          "Your preference was saved, but macOS did not change the default application. Try again and approve any system confirmation. You can also select a .md file in Finder, choose Get Info → Open with → \(self.applicationName(target)), then Change All…."))
        return
      }
      completion(nil)
    }
  }

  private func previousApplication() -> URL? {
    guard
      let stored = defaults.string(forKey: previousApplicationKey),
      let url = URL(string: stored), url.isFileURL,
      !isLinefold(url), workspace.applicationExists(url)
    else { return nil }
    return url
  }

  private func isLinefold(_ url: URL?) -> Bool {
    sameApplication(url, applicationURL)
  }

  private func sameApplication(_ first: URL?, _ second: URL) -> Bool {
    guard let first else { return false }
    if let firstID = Bundle(url: first)?.bundleIdentifier,
       let secondID = Bundle(url: second)?.bundleIdentifier {
      return firstID == secondID
    }
    return first.standardizedFileURL == second.standardizedFileURL
  }

  private func applicationName(_ application: URL) -> String {
    let bundle = Bundle(url: application)
    return bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? application.deletingPathExtension().lastPathComponent
  }
}

private struct AssociationError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

/// Finder may send open events before Flutter and workspace recovery are ready.
final class IncomingMarkdownFiles {
  static let shared = IncomingMarkdownFiles()
  var onFilesAvailable: (() -> Void)?
  private var pending: [String] = []
  private var securityScopedURLs: [String: URL] = [:]

  func receive(_ urls: [URL]) {
    for url in urls where url.isFileURL {
      guard ["md", "markdown", "mdown", "mkd", "txt"].contains(url.pathExtension.lowercased()) else { continue }
      if securityScopedURLs[url.path] == nil, url.startAccessingSecurityScopedResource() {
        securityScopedURLs[url.path] = url
      }
      pending.append(url.path)
    }
    if !pending.isEmpty { onFilesAvailable?() }
  }

  func takePendingFiles() -> [String] {
    let files = pending
    pending.removeAll()
    return files
  }

  deinit {
    for url in securityScopedURLs.values { url.stopAccessingSecurityScopedResource() }
  }
}

/// Shared with native acceptance tests; FileManager never replaces a destination.
enum WorkspaceFileOperations {
  static func perform(_ operation: String, arguments: [String: Any]) throws -> String? {
    guard let path = arguments["path"] as? String, !path.isEmpty else {
      throw CocoaError(.fileNoSuchFile)
    }
    let manager = FileManager.default
    let url = URL(fileURLWithPath: path).standardizedFileURL
    switch operation {
    case "createEntry":
      if arguments["directory"] as? Bool == true {
        // mkdir fails on an existing name, including a racing create.
        guard mkdir(url.path, 0o777) == 0 else {
          throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
      } else {
        try Data((arguments["contents"] as? String ?? "").utf8)
          .write(to: url, options: .withoutOverwriting)
      }
    case "moveEntry", "copyEntry":
      guard let destination = arguments["destination"] as? String, !destination.isEmpty else {
        throw CocoaError(.fileNoSuchFile)
      }
      let target = URL(fileURLWithPath: destination).standardizedFileURL
      if target.path == url.path || target.path.hasPrefix(url.path + "/") {
        throw CocoaError(.fileWriteInvalidFileName)
      }
      if operation == "moveEntry" {
        try manager.moveItem(at: url, to: target)
      } else {
        try manager.copyItem(at: url, to: target)
      }
    case "trashEntry":
      var trashed: NSURL?
      try manager.trashItem(at: url, resultingItemURL: &trashed)
      return trashed?.path
    default:
      throw CocoaError(.featureUnsupported)
    }
    return nil
  }
}

/// Launch Services discovers embedded extensions when the installed app opens.
/// Election belongs to macOS; never invoke registration tools from the sandbox.
final class FinderPreviewSetup {
  private let defaults = UserDefaults.standard
  private let key = "finderPreview.setupSeen.v1"

  func state() -> [String: Any] {
    let app = Bundle.main.bundleURL
    let applicationFolders = FileManager.default.urls(for: .applicationDirectory, in: [.localDomainMask, .userDomainMask])
    let installed = applicationFolders.contains { app.path.hasPrefix($0.path + "/") }
    let extensionURL = app.appendingPathComponent("Contents/PlugIns/LinefoldQuickLook.appex")
    let bundled = FileManager.default.fileExists(atPath: extensionURL.path)
    return ["needsSetup": !defaults.bool(forKey: key), "installed": installed,
            "bundled": bundled]
  }

  func dismissSetup() { defaults.set(true, forKey: key) }

  func openSettings() -> Bool {
    if #available(macOS 15, *) {
      SMAppService.openSystemSettingsLoginItems()
      return true
    }
    return NSWorkspace.shared.open(URL(string:
      "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.quicklook.preview")!)
  }

  func revealExample(completion: @escaping (Error?) -> Void) {
    // A user-selected location lets Finder and the preview extension access the
    // sample without relying on access to the host application's private container.
    let panel = NSSavePanel()
    panel.title = "Save Finder Preview Sample"
    panel.nameFieldStringValue = "Linefold Preview.md"
    panel.allowedContentTypes = [UTType(importedAs: "net.daringfireball.markdown")]
    panel.canCreateDirectories = true
    panel.begin { response in
      guard response == .OK, let file = panel.url else { completion(nil); return }
      do {
        try """
        # Linefold Finder Preview

        This sentence contains **bold text**.

        | Feature | Result |
        | --- | --- |
        | Markdown preview | Ready |
        """.write(to: file, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([file])
        completion(nil)
      } catch { completion(error) }
    }
  }
}
