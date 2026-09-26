import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func application(_ application: NSApplication, open urls: [URL]) {
    let files = urls.filter(\.isFileURL)
    IncomingMarkdownFiles.shared.receive(files)
    let otherURLs = urls.filter { !$0.isFileURL }
    if !otherURLs.isEmpty { super.application(application, open: otherURLs) }
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    application.activate(ignoringOtherApps: true)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
