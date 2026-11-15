import Cocoa
import CryptoKit
import FlutterMacOS
import XCTest
@testable import fido

class RunnerTests: XCTestCase {
  func testUpdaterReleasesRemovedCoordinationMessagesAndWatcher() throws {
    let manager = FileManager.default
    let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let object = Bundle.main.bundleURL.standardizedFileURL.path
    let hash = SHA256.hash(data: Data(object.utf8)).map { String(format: "%02x", $0) }.joined()
    let directory = support.appendingPathComponent("FFIDO/Updates/" + hash)
    var updater: ManagedUpdater? = ManagedUpdater(profile: "lifecycle-test", canExit: { $0(false) }, progress: { _, _ in })
    let released = { [weak updater] in updater == nil }
    func seen() -> Set<String> {
      guard let updater else { return [] }
      return Mirror(reflecting: updater).children.first { $0.label == "seenMessages" }?.value as? Set<String> ?? []
    }
    func awaitMessage(_ name: String) {
      let deadline = Date().addingTimeInterval(3)
      while !seen().contains(name) && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.005))
      }
      XCTAssertTrue(seen().contains(name), "The real filesystem watcher must process the test message")
    }
    var owned: [URL] = []
    defer { for file in owned { try? manager.removeItem(at: file) } }
    for _ in 0..<20 {
      let first = directory.appendingPathComponent("message-" + UUID().uuidString + ".json")
      let next = directory.appendingPathComponent("message-" + UUID().uuidString + ".json")
      owned += [first, next]
      // An invalid peer exercises parsing/deduplication without any update or profile action.
      try Data("{\"pid\":\"-1\"}".utf8).write(to: first, options: .atomic)
      awaitMessage(first.lastPathComponent)
      try manager.removeItem(at: first)
      try Data("{\"pid\":\"-1\"}".utf8).write(to: next, options: .atomic)
      awaitMessage(next.lastPathComponent)
      XCTAssertFalse(seen().contains(first.lastPathComponent), "Removed update cycles must not accumulate in memory")
      try manager.removeItem(at: next)
    }
    updater = nil
    XCTAssertTrue(released(), "The watcher must not retain its updater")
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
  }
}
