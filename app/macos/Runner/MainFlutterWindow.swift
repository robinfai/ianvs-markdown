import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var benchmarkObservers: [NSObjectProtocol] = []
  private var benchmarkState: NSDictionary?
  private var benchmarkGeneration = 0
  private var benchmarkChannel: FlutterMethodChannel?

  // Read-only, opt-in instrumentation. Ordinary launches install no observers.
  private func benchmarkSnapshot() -> [String: Any] {
    let state: [String: Any] = [
      "active": NSApp.isActive,
      "visible": isVisible,
      "miniaturized": isMiniaturized,
      "occlusionVisible": occlusionState.contains(.visible),
      "onActiveSpace": isOnActiveSpace,
      "appHidden": NSApp.isHidden,
      "x": frame.origin.x,
      "y": frame.origin.y,
      "screen": screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? Int ?? -1,
      "scale": backingScaleFactor,
      "width": frame.width,
      "height": frame.height,
    ]
    let current = state as NSDictionary
    if let previous = benchmarkState, !previous.isEqual(current) {
      benchmarkGeneration += 1
    }
    benchmarkState = current
    return state.merging(["generation": benchmarkGeneration]) { _, new in new }
  }

  private func observeBenchmarkEnvironment() {
    guard benchmarkObservers.isEmpty else { return }
    let names: [Notification.Name] = [
      NSApplication.didBecomeActiveNotification,
      NSApplication.didResignActiveNotification,
      NSApplication.didHideNotification,
      NSApplication.didUnhideNotification,
      NSWindow.didChangeOcclusionStateNotification,
      NSWindow.didMiniaturizeNotification,
      NSWindow.didDeminiaturizeNotification,
      NSWindow.didResizeNotification,
      NSWindow.didMoveNotification,
    ]
    for name in names {
      benchmarkObservers.append(NotificationCenter.default.addObserver(
        forName: name, object: nil, queue: .main
      ) { [weak self] _ in
        guard let self = self else { return }
        let generation = self.benchmarkGeneration
        let state = self.benchmarkSnapshot()
        if self.benchmarkGeneration != generation {
          self.benchmarkChannel?.invokeMethod("changed", arguments: state)
        }
      })
    }
  }


  private var fileAccessChannel: FlutterMethodChannel?
  private var fileAssociationChannel: FlutterMethodChannel?
  private var incomingFilesChannel: FlutterMethodChannel?
  private let fileAssociation = MarkdownFileAssociation()
  private var securityScopedURLs: [String: URL] = [:]

  // macOS 27: TextKit 2 lays out a full-document selection when Flutter's
  // hidden accessibility field starts editing. Use AppKit's compatibility
  // path only for this engine view, before activation and outside composition.
  // The full string, selection and semantics stay intact. Remove/revalidate
  // when changing macOS or Flutter; see benchmark/NATIVE-TEXT-LIFECYCLE-2026-10-14.md.
  override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
    if #available(macOS 12.0, *),
       ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27,
       let text = responder as? NSTextView,
       NSStringFromClass(type(of: text)) == "FlutterTextInputPlugin",
       text.window === self, text.frame.width == 0,
       !text.hasMarkedText(), text.textLayoutManager != nil {
      _ = text.layoutManager
    }
    return super.makeFirstResponder(responder)
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = false
    self.acceptsMouseMovedEvents = true
    self.minSize = NSSize(width: 840, height: 560)
    self.setContentSize(NSSize(width: 1200, height: 780))
    self.center()
    if #available(macOS 11.0, *) {
      self.titlebarSeparatorStyle = .none
      self.toolbarStyle = .unified
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    CloudWorkspace.shared.attach(to: flutterViewController.engine.binaryMessenger)
    registerFileAccessChannel(with: flutterViewController)
    registerDesktopIntegration(with: flutterViewController)

    benchmarkChannel = FlutterMethodChannel(
      name: "ianvs_markdown/benchmark_environment",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    benchmarkChannel?.setMethodCallHandler { [weak self] call, result in
      if call.method == "inputSnapshot", let self = self {
        var info: [String: Any] = ["responder": String(describing: type(of: self.firstResponder))]
        if let text = self.firstResponder as? NSTextView {
          info["class"] = NSStringFromClass(type(of: text))
          info["textLength"] = text.string.utf16.count
          info["selectionLocation"] = text.selectedRange().location
          info["selectionLength"] = text.selectedRange().length
          info["fieldEditor"] = text.isFieldEditor
          info["width"] = text.frame.width
          info["height"] = text.frame.height
          info["containerWidth"] = text.textContainer?.containerSize.width ?? -1
          info["containerHeight"] = text.textContainer?.containerSize.height ?? -1
          if #available(macOS 12.0, *) {
            info["textKit2"] = text.textLayoutManager != nil
          }
        }
        result(info)
        return
      }
      guard call.method == "snapshot", let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.observeBenchmarkEnvironment()
      result(self.benchmarkSnapshot())
    }

    super.awakeFromNib()
  }

  override func sendEvent(_ event: NSEvent) {
    // AppKit otherwise consumes clicks in Flutter's top row as titlebar drags.
    // Update before mouse-down so WindowServer uses the correct drag region.
    // The first 168 points retain the native buttons and app-name drag area.
    let point = event.locationInWindow
    let isHeaderControl = NSRect(
      x: 168, y: frame.height - 44, width: frame.width - 168, height: 44
    ).contains(point)
    switch event.type {
    case .mouseMoved, .mouseEntered, .mouseExited, .leftMouseDown, .rightMouseDown:
      isMovable = !isHeaderControl
    default:
      break
    }
    super.sendEvent(event)
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
        case "createEntry", "moveEntry", "copyEntry", "trashEntry":
          result(try WorkspaceFileOperations.perform(call.method, arguments: arguments))
        case "revealInFinder":
          guard let path = arguments["path"] as? String, !path.isEmpty else {
            throw FileAccessError.missingValue("path")
          }
          NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
          result(nil)
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
    for observer in benchmarkObservers {
      NotificationCenter.default.removeObserver(observer)
    }
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
