import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var benchmarkObservers: [NSObjectProtocol] = []
  private var benchmarkState: NSDictionary?
  private var benchmarkGeneration = 0
  private var benchmarkChannel: FlutterMethodChannel?

  // Read-only, opt-in instrumentation for the profile benchmark. Ordinary
  // example entry points never invoke this channel or install observers.
  private func benchmarkSnapshot() -> [String: Any] {
    let state: [String: Any] = [
      "active": NSApp.isActive,
      "visible": isVisible,
      "miniaturized": isMiniaturized,
      "occlusionVisible": occlusionState.contains(.visible),
      "onActiveSpace": isOnActiveSpace,
      "appHidden": NSApp.isHidden,
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
