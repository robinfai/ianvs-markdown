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

  deinit {
    for observer in benchmarkObservers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

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
    self.title = "Ianvs Markdown Playground"
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true
    self.minSize = NSSize(width: 860, height: 620)
    self.setContentSize(NSSize(width: 1180, height: 780))
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
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
}
