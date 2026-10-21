import Cocoa
import FlutterMacOS
#if FFIDO_UPDATER_TESTING
import Security
import LocalAuthentication
#endif

class MainFlutterWindow: NSWindow {
  private var managedUpdater: ManagedUpdater?
  private var updatesChannel: FlutterMethodChannel?
  private var profileLease: ProfileLease?
  private var profileChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    if ManagedUpdater.installInProgress() {
      let alert = NSAlert(); alert.messageText = "FFIDO обновляется"
      alert.informativeText = "Дождитесь завершения обновления и откройте профиль снова."
      alert.runModal(); exit(EXIT_FAILURE)
    }
    let arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
    let explicitProfile = arguments.contains { $0 == "--profile" || $0.hasPrefix("--profile=") }
    let restored = explicitProfile ? [] : ManagedUpdater.restoration()
    let profile: LaunchProfile
    do {
      profile = try LaunchProfile(arguments: !restored.isEmpty ? ["--profile", restored[0]] : arguments)
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
    let updates = FlutterMethodChannel(name: "ffido/updates", binaryMessenger: flutterViewController.engine.binaryMessenger)
    let managed = ManagedUpdater(profile: profile.id, canExit: { reply in
      updates.invokeMethod("canExit", arguments: nil) { value in reply(value as? Bool == true) }
    }, progress: { stage, progress in
      updates.invokeMethod("progress", arguments: ["stage": stage, "progress": progress])
    })
    managedUpdater = managed
    updatesChannel = updates
    updates.setMethodCallHandler { call, result in
#if FFIDO_UPDATER_TESTING
      if call.method == "testBundleID" { result(Bundle.main.bundleIdentifier); return }
      if call.method == "testKeychainRead", let fields = call.arguments as? [String: String],
         let account = fields["account"], let expected = fields["expected"] {
        // Match SecureSessionStore's login-Keychain query and request a
        // noninteractive read; only this test process supplies the LAContext.
        let context = LAContext(); context.interactionNotAllowed = true
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword,
          kSecAttrAccount: account, kSecAttrService: "flutter_secure_storage_service",
          kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked, kSecAttrSynchronizable: false,
          kSecUseDataProtectionKeychain: false, kSecReturnData: true,
          kSecUseAuthenticationContext: context]
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        result(["status": status, "matches": (value as? Data) == expected.data(using: .utf8)])
        return
      }
      if call.method == "testMark" {
        do {
          let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
          let directory = support.appendingPathComponent("FFIDO/UpdaterQA")
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          var record = call.arguments as? [String: Any] ?? [:]
          record["version"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
          record["pid"] = getpid(); record["profile"] = profile.id
          let data = try JSONSerialization.data(withJSONObject: record)
          try data.write(to: directory.appendingPathComponent(profile.id + ".json"), options: .atomic)
          result(directory.path)
        } catch { result(FlutterError(code: "qa", message: error.localizedDescription, details: nil)) }
        return
      }
#endif
      if call.method == "cancel" { managed.cancel(); result(nil); return }
      guard call.method == "installMacOS", let fields = call.arguments as? [String: String],
            let url = fields["url"], let key = fields["publicKey"], let version = fields["version"], let package = fields["packageURL"] else { result(FlutterMethodNotImplemented); return }
      managed.install(url: url, publicKey: key, version: version, packageURL: package) { error in
        if let error {
          let issue = error as NSError
          let message = [issue.localizedDescription, issue.localizedRecoverySuggestion].compactMap { $0 }.joined(separator: "\n")
          result(FlutterError(code: "update", message: message, details: ["domain": issue.domain, "code": issue.code]))
        }
        else { result(nil) }
      }
    }
    do { try ManagedUpdater.openProfiles(restored.filter { $0 != profile.id }) }
    catch {
      let alert = NSAlert(); alert.messageText = "Не удалось восстановить остальные профили"
      alert.informativeText = error.localizedDescription; alert.runModal()
    }
    profileChannel = channel
    super.awakeFromNib()
  }
}
