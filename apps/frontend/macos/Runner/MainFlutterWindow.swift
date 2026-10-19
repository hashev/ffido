import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var profileLease: ProfileLease?
  private var profileChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let profile: LaunchProfile
    do {
      profile = try LaunchProfile(arguments: Array(ProcessInfo.processInfo.arguments.dropFirst()))
      let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                in: .userDomainMask, appropriateFor: nil, create: true)
      profileLease = try ProfileLease(directory: support.appendingPathComponent("FFIDO/ProfileLocks"),
                                     profile: profile)
    } catch {
      let alert = NSAlert()
      alert.messageText = "Не удалось открыть FFIDO"
      alert.informativeText = error.localizedDescription
      alert.runModal()
      exit(EXIT_FAILURE)
    }
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.title = "FFIDO [\(profile.id)]"
    RegisterGeneratedPlugins(registry: flutterViewController)
    let channel = FlutterMethodChannel(name: "ffido/desktop_profile",
                                       binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getProfile": result(profile.id)
      case "setIdentity":
        let fields = call.arguments as? [String: String] ?? [:]
        let name = fields["name"] ?? ""
        let address = fields["address"] ?? ""
        self?.title = name.isEmpty || address.isEmpty
          ? "FFIDO [\(profile.id)]" : "FFIDO — \(name) (\(address)) [\(profile.id)]"
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    profileChannel = channel
    super.awakeFromNib()
  }
}
