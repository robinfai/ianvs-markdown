import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var fileAccessChannel: FlutterMethodChannel?
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

    super.awakeFromNib()
  }

  private func registerFileAccessChannel(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.ianvs.markdown/file_access",
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
