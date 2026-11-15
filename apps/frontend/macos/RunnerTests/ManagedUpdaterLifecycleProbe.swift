// Standalone native watcher test; compile with ManagedUpdater.swift and LaunchProfile.swift.
import Cocoa
import CryptoKit

@main
struct ManagedUpdaterLifecycleProbe {
  final class WatcherReference {
    weak var value: ManagedUpdater?
    init(_ value: ManagedUpdater?) { self.value = value }
  }
  enum Failure: Error { case timeout(String), retainedWatcher, duplicateCompletion, descriptors }
  static func wait(_ label: String, until predicate: () -> Bool) throws {
    let deadline = Date().addingTimeInterval(3)
    while !predicate() {
      if Date() >= deadline { throw Failure.timeout(label) }
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
  }
  static func descriptors() -> Int {
    (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? 0
  }
  static func main() throws {
    _ = NSApplication.shared
    let path = Bundle.main.bundleURL.standardizedFileURL.path
    let hash = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let directory = support.appendingPathComponent("FFIDO/Updates/" + hash)
    // This executable lives in an isolated QA bundle; never touch another bundle's directory.
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let before = descriptors()
    var completions = 0
    for round in 0..<20 {
      var instance: ManagedUpdater? = ManagedUpdater(profile: "lifecycle-qa", canExit: { $0(true) }, progress: { _, _ in })
      let reference = WatcherReference(instance)
      for index in 0..<50 {
        let file = directory.appendingPathComponent("message-\(round)-\(index).json")
        try JSONSerialization.data(withJSONObject: ["pid": "0", "token": UUID().uuidString, "action": "reply"])
          .write(to: file, options: .atomic)
      }
      try wait("observe fifty messages") { instance!.seenMessages.count == 50 }
      for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
        if file.lastPathComponent.hasPrefix("message-") { try FileManager.default.removeItem(at: file) }
      }
      try wait("forget deleted messages") { instance!.seenMessages.isEmpty }
      instance!.install(url: "invalid", publicKey: "", version: "1", packageURL: "invalid") { _ in completions += 1 }
      instance!.cancel(); instance!.cancel()
      instance = nil
      guard reference.value == nil else { throw Failure.retainedWatcher }
      RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    guard completions == 20 else { throw Failure.duplicateCompletion }
    let after = descriptors()
    guard after <= before + 1 else { throw Failure.descriptors }
    let report: [String: Any] = ["rounds": 20, "messages": 1000, "peakRemembered": 50,
                                "retainedRemembered": 0, "completions": completions,
                                "descriptorsBefore": before, "descriptorsAfter": after, "releasedWatchers": 20]
    print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), encoding: .utf8)!)
  }
}
