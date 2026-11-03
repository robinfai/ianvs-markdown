import XCTest
@testable import Linefold

class RunnerTests: XCTestCase {
  func testUpdateConfigurationRequiresKeyAndHTTPS() {
    let key = Data(repeating: 1, count: 32).base64EncodedString()
    let valid: [String: Any] = ["SUPublicEDKey": key,
      "SUFeedURL": "https://github.com/robinfai/ianvs-markdown/releases/download/linefold-v0.1.2/appcast.xml"]
    XCTAssertNil(SoftwareUpdateController.configurationError(info: valid, bundleIdentifier: "work.ianvs.linefold"))
    XCTAssertNotNil(SoftwareUpdateController.configurationError(info: [:], bundleIdentifier: "work.ianvs.linefold"))
    for feed in ["http://127.0.0.1:9123/appcast.xml", "https://user:password@example.com/feed", "file:///tmp/feed"] {
      XCTAssertNotNil(SoftwareUpdateController.configurationError(
        info: ["SUPublicEDKey": key, "SUFeedURL": feed], bundleIdentifier: "work.ianvs.linefold"))
    }
    XCTAssertNil(SoftwareUpdateController.configurationError(
      info: ["SUPublicEDKey": key, "SUFeedURL": "http://127.0.0.1:9123/appcast.xml"],
      bundleIdentifier: "work.ianvs.linefold.update-test"))
  }
}
