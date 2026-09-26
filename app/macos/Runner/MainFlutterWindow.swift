import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var fileAccessChannel: FlutterMethodChannel?
  private var fileAssociationChannel: FlutterMethodChannel?
  private var incomingFilesChannel: FlutterMethodChannel?
  private let fileAssociation = MarkdownFileAssociation()
  private var securityScopedURLs: [String: URL] = [:]

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true
    self.minSize = NSSize(width: 840, height: 560)
    self.setContentSize(NSSize(width: 1200, height: 780))
    self.center()
    if #available(macOS 11.0, *) {
      self.titlebarSeparatorStyle = .none
      self.toolbarStyle = .unified
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerFileAccessChannel(with: flutterViewController)
    registerDesktopIntegration(with: flutterViewController)

    super.awakeFromNib()
  }

  private func registerDesktopIntegration(with controller: FlutterViewController) {
    let preferences = FlutterMethodChannel(
      name: "work.ianvs.linefold/file_association",
      binaryMessenger: controller.engine.binaryMessenger)
    preferences.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "getState":
        result(self.fileAssociation.state())
      case "setPreference":
        guard let arguments = call.arguments as? [String: Any],
              let preferLinefold = arguments["preferLinefold"] as? Bool else {
          result(FlutterError(code: "invalid_arguments", message: "Missing preferLinefold", details: nil))
          return
        }
        self.fileAssociation.setPreference(preferLinefold) { [weak self] error in
          guard let self else { return }
          if let error {
            result(FlutterError(code: "association_failed", message: error.localizedDescription, details: nil))
          } else {
            result(self.fileAssociation.state())
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    fileAssociationChannel = preferences

    let incoming = FlutterMethodChannel(
      name: "work.ianvs.linefold/open_files",
      binaryMessenger: controller.engine.binaryMessenger)
    incoming.setMethodCallHandler { call, result in
      if call.method == "takePendingFiles" {
        result(IncomingMarkdownFiles.shared.takePendingFiles())
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    IncomingMarkdownFiles.shared.onFilesAvailable = { [weak incoming] in
      incoming?.invokeMethod("filesAvailable", arguments: nil)
    }
    incomingFilesChannel = incoming
  }

  private func registerFileAccessChannel(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "work.ianvs.linefold/file_access",
      binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      guard let arguments = call.arguments as? [String: Any] else {
        result(FlutterError(
          code: "invalid_arguments",
          message: "Missing arguments",
          details: nil))
        return
      }

      do {
        switch call.method {
        case "openExternal":
          guard let value = arguments["url"] as? String,
                let url = URL(string: value),
                let scheme = url.scheme?.lowercased(),
                ["http", "https", "mailto", "file"].contains(scheme),
                scheme != "file" || ["html", "htm", "pdf", "svg"].contains(url.pathExtension.lowercased()) else {
            throw FileAccessError.missingValue("supported url")
          }
          if NSWorkspace.shared.open(url) {
            result(nil)
          } else {
            result(FlutterError(code: "open_failed", message: "No application could open this link.", details: nil))
          }
        case "createBookmark":
          guard let path = arguments["path"] as? String else {
            throw FileAccessError.missingValue("path")
          }
          let data = try URL(fileURLWithPath: path).bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil)
          result(data.base64EncodedString())
        case "resolveBookmark":
          guard
            let token = arguments["token"] as? String,
            let data = Data(base64Encoded: token)
          else {
            throw FileAccessError.missingValue("token")
          }
          var isStale = false
          let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale)
          if securityScopedURLs[url.path] == nil,
             url.startAccessingSecurityScopedResource() {
            securityScopedURLs[url.path] = url
          }
          result(url.path)
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(
          code: "file_access_failed",
          message: error.localizedDescription,
          details: nil))
      }
    }
    fileAccessChannel = channel
  }

  deinit {
    for url in securityScopedURLs.values {
      url.stopAccessingSecurityScopedResource()
    }
  }
}

private enum FileAccessError: LocalizedError {
  case missingValue(String)

  var errorDescription: String? {
    switch self {
    case .missingValue(let name):
      return "Missing \(name)"
    }
  }
}
