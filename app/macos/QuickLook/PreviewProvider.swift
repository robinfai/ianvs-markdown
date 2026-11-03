import Foundation

// Shared by the extension and the native boundary tests.
enum MarkdownPreview {
  static let maximumBytes = 2 * 1024 * 1024
  static func source(for url: URL) throws -> String {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
      throw CocoaError(.fileReadUnsupportedScheme)
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let bytes = try handle.read(upToCount: maximumBytes + 1) ?? Data()
    guard bytes.count <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
    let text: String?
    if bytes.starts(with: [0xff, 0xfe]) || bytes.starts(with: [0xfe, 0xff]) {
      text = String(data: bytes, encoding: .utf16)
    } else {
      text = String(data: bytes.starts(with: [0xef, 0xbb, 0xbf]) ? Data(bytes.dropFirst(3)) : bytes, encoding: .utf8)
    }
    guard let text else { throw CocoaError(.fileReadInapplicableStringEncoding) }
    return text
  }
}

#if !QUICKLOOK_READER_TEST
import Cocoa
import QuickLookUI
import FlutterMacOS
import os

final class PreviewProvider: NSViewController, QLPreviewingController {
  private let logger = Logger(subsystem: "work.ianvs.linefold.QuickLook", category: "preview")
  private var engine: FlutterEngine?
  private var flutter: FlutterViewController?
  private var channel: FlutterMethodChannel?
  private var completion: ((Error?) -> Void)?
  private var generation = UUID()
  private var documentURL: URL?
  private var scoped = false
  override func loadView() { view = NSView(frame: NSRect(x: 0, y: 0, width: 820, height: 900)) }

  func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
    releasePreview()
    let token = UUID()
    generation = token
    completion = handler
    do {
      let source = try MarkdownPreview.source(for: url)
      documentURL = url
      scoped = url.startAccessingSecurityScopedResource()
      let bundle = Bundle(for: PreviewProvider.self)
      guard let frameworks = bundle.privateFrameworksURL,
            let dartBundle = Bundle(url: frameworks.appendingPathComponent("App.framework")) else {
        throw CocoaError(.fileNoSuchFile)
      }
      let payload = try JSONSerialization.data(withJSONObject: [
        "source": source, "merman": frameworks.appendingPathComponent("libmerman_ffi.dylib").path
      ])
      let project = FlutterDartProject(precompiledDartBundle: dartBundle)
      project.dartEntrypointArguments = [payload.base64EncodedString()]
      let engine = FlutterEngine(name: "LinefoldQuickLook", project: project, allowHeadlessExecution: false)
      self.engine = engine
      let channel = FlutterMethodChannel(name: "work.ianvs.linefold.quicklook", binaryMessenger: engine.binaryMessenger)
      self.channel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self, self.generation == token else { result(nil); return }
        switch call.method {
        case "firstFrame": self.finish(nil); result(nil)
        case "image": result(self.image(call.arguments as? String))
        default: result(FlutterMethodNotImplemented)
        }
      }
      let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
      flutter = controller
      addChild(controller)
      controller.view.frame = view.bounds
      controller.view.autoresizingMask = [.width, .height]
      view.addSubview(controller.view)
      guard engine.run(withEntrypoint: nil) else { throw CocoaError(.executableLoad) }
      preferredContentSize = NSSize(width: 820, height: 900)
      DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
        guard let self, self.generation == token, self.completion != nil else { return }
        self.finish(CocoaError(.executableRuntimeMismatch))
        self.releasePreview()
      }
    } catch { finish(error); releasePreview() }
  }

  private func finish(_ error: Error?) {
    let callback = completion
    completion = nil
    if let error { logger.error("Preview failed: \(error.localizedDescription, privacy: .public)") }
    callback?(error)
  }

  // Never fetch network URLs or widen access beyond the document directory.
  // Finder's sandbox may deny sibling files; return a placeholder in that case.
  private func image(_ value: String?) -> FlutterStandardTypedData? {
    guard let value, let documentURL, let relative = URL(string: value), relative.scheme == nil,
          !value.hasPrefix("/"), !value.hasPrefix("//") else { return nil }
    let directory = documentURL.deletingLastPathComponent().resolvingSymlinksInPath()
    let target = URL(string: value, relativeTo: directory.appendingPathComponent("", isDirectory: true))!.absoluteURL.resolvingSymlinksInPath()
    guard target.path.hasPrefix(directory.path + "/"),
          let handle = try? FileHandle(forReadingFrom: target) else { return nil }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: 8 * 1024 * 1024 + 1), data.count <= 8 * 1024 * 1024 else { return nil }
    return FlutterStandardTypedData(bytes: data)
  }

  private func releasePreview() {
    generation = UUID()
    finish(CocoaError(.userCancelled))
    channel?.setMethodCallHandler(nil)
    channel = nil
    flutter?.view.removeFromSuperview()
    flutter?.removeFromParent()
    flutter = nil
    engine?.shutDownEngine()
    engine = nil
    if scoped, let documentURL { documentURL.stopAccessingSecurityScopedResource() }
    scoped = false
    documentURL = nil
  }
  deinit { releasePreview() }
}
#endif
