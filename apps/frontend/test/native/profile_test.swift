import Foundation
import Darwin

@main
struct ProfileTests {
  static func main() throws {
    if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--hold" {
      let lease = try ProfileLease(directory: URL(fileURLWithPath: CommandLine.arguments[2]),
                                   profile: LaunchProfile(arguments: ["--profile=crash"]))
      print("held")
      fflush(stdout)
      withExtendedLifetime(lease) { _ = sleep(30) }
      return
    }
    for (args, expected) in [([], "default"), (["--profile", "point1"], "point1"),
                             (["--profile=point2"], "point2"), (["-psn_1", "--profile=default"], "default")] {
      let parsed = try LaunchProfile(arguments: args)
      assert(parsed.id == expected)
    }
    for args in [["--profile"], ["--profile="], ["--profile", "../x"], ["--profile=Upper"],
                 ["--profile=x", "--profile=y"], ["--profile=x\n"], ["--profile=x\r"], ["--profile=x\u{2028}"], ["--profile=" + String(repeating: "x", count: 33)]] {
      do { _ = try LaunchProfile(arguments: args); fatalError("Accepted invalid args") }
      catch ProfileError.invalid {}
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let profile = try LaunchProfile(arguments: ["--profile=point1"])
    var first: ProfileLease? = try ProfileLease(directory: root, profile: profile)
    withExtendedLifetime(first) {
      do { _ = try ProfileLease(directory: root, profile: profile); fatalError("Double lease") }
      catch ProfileError.busy(_) {} catch { fatalError("Wrong error: \(error)") }
    }
    let second = try ProfileLease(directory: root, profile: LaunchProfile(arguments: ["--profile=point2"]))
    withExtendedLifetime(second) {}
    first = nil
    let reopened = try ProfileLease(directory: root, profile: profile)
    withExtendedLifetime(reopened) {}
    let file = root.appendingPathComponent("file")
    try Data().write(to: file)
    do { _ = try ProfileLease(directory: file, profile: profile); fatalError("Non-directory accepted") }
    catch {}
    let child = Process()
    child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    child.arguments = ["--hold", root.path]
    let output = Pipe()
    child.standardOutput = output
    try child.run()
    let signal = output.fileHandleForReading.readData(ofLength: 5)
    assert(String(data: signal, encoding: .utf8) == "held\n")
    kill(child.processIdentifier, SIGKILL)
    child.waitUntilExit()
    let afterCrash = try ProfileLease(directory: root, profile: LaunchProfile(arguments: ["--profile=crash"]))
    withExtendedLifetime(afterCrash) {}
    print("Native profiles: arguments, exclusive leases, independent profiles, release, storage failure passed")
  }
}
