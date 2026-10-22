import Cocoa
import CryptoKit
import Darwin
import Sparkle

final class ManagedUpdater: NSObject, SPUUserDriver, SPUUpdaterDelegate {
  private var cancellation: (() -> Void)?
  private var updater: SPUUpdater?
  private var finish: ((Error?) -> Void)?
  private var feed = "", wantedVersion = "", packageURL = ""
  private var updateLock: Int32 = -1
  private var expected = Set<Int32>()
  private var replies: [Int32: (Bool, String)] = [:]
  private var token = "", preparedToken = ""
  private var relaunchProfiles = Set<String>()
  private var watcher: DispatchSourceFileSystemObject?
  private var seenMessages = Set<String>()
  private var downloaded: UInt64 = 0, total: UInt64 = 0
  private let profile: String
  private let canExit: (@escaping (Bool) -> Void) -> Void
  private let progress: (String, Double) -> Void
  private var object: String { Bundle.main.bundleURL.standardizedFileURL.path }
  private var directory: URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let hash = SHA256.hash(data: Data(object.utf8)).map { String(format: "%02x", $0) }.joined()
    return support.appendingPathComponent("FFIDO/Updates/" + hash)
  }
  private func activeProfiles() throws -> [Int32: String] {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let locks = support.appendingPathComponent("FFIDO/ProfileLocks")
    let files = try FileManager.default.contentsOfDirectory(at: locks, includingPropertiesForKeys: nil)
    var profiles: [Int32: String] = [:]
    for file in files where file.pathExtension == "lock" {
      let fd = open(file.path, O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
      guard fd >= 0 else { throw failure("Не удалось проверить работающие профили") }
      defer { close(fd) }
      if flock(fd, LOCK_EX | LOCK_NB) == 0 { continue }
      guard errno == EWOULDBLOCK else { throw failure("Не удалось проверить блокировку профиля") }
      var bytes = [UInt8](repeating: 0, count: 4097)
      let count = read(fd, &bytes, bytes.count)
      guard count > 0 && count <= 4096,
            let record = try? JSONSerialization.jsonObject(with: Data(bytes.prefix(count))) as? [String: Any],
            let pid = record["pid"] as? Int32, pid > 0,
            let profile = record["profile"] as? String,
            profile == file.deletingPathExtension().lastPathComponent,
            (try? LaunchProfile(arguments: ["--profile", profile])) != nil,
            let bundle = record["bundle"] as? String else {
        throw failure("Другое окно запускается или не поддерживает обновление; закройте его и повторите")
      }
      // The held inode lock proves liveness. Sandbox may reject kill(pid, 0)
      // for another instance, even when both instances share this container.
      if bundle == object { profiles[pid] = profile }
    }
    return profiles
  }
  init(profile: String, canExit: @escaping (@escaping (Bool) -> Void) -> Void,
       progress: @escaping (String, Double) -> Void) {
    self.profile = profile; self.canExit = canExit; self.progress = progress
    super.init()
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      let fd = open(directory.path, O_EVTONLY | O_CLOEXEC)
      if fd >= 0 {
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in self?.receiveMessages() }
        source.setCancelHandler { close(fd) }
        watcher = source; source.resume()
      }
    } catch { /* Installation reports the inaccessible coordination directory. */ }
  }
  deinit { watcher?.cancel(); unlock() }
  private func failure(_ text: String) -> NSError { NSError(domain: "FFIDO.Update", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
  private func unlock() { if updateLock >= 0 { close(updateLock); updateLock = -1 } }
  private func end(_ error: Error?) {
    let callback = finish; finish = nil; cancellation = nil; updater = nil; unlock()
    if error != nil {
      let active = Set((try? activeProfiles().values.map { $0 }) ?? [])
      try? Self.openProfiles(relaunchProfiles.filter { $0 != profile && !active.contains($0) }.sorted())
    }
    relaunchProfiles = []; callback?(error)
  }
  func cancel() { cancellation?(); end(failure("Обновление отменено")) }
  private func allowedFeed(_ url: URL) -> Bool {
#if FFIDO_UPDATER_TESTING
    if url.scheme == "http" && url.host == "127.0.0.1" { return true }
#endif
    return url.scheme == "https" && url.host == "github.com" && url.path.hasPrefix("/hashev/ffido/releases/download/")
  }
  func install(url: String, publicKey: String, version: String, packageURL: String, completion: @escaping (Error?) -> Void) {
    guard watcher != nil else { completion(failure("Не удалось наблюдать за состоянием других профилей")); return }
    guard finish == nil else { completion(failure("Обновление уже выполняется")); return }
    guard Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String == publicKey, !publicKey.isEmpty,
          let parsed = URL(string: url), allowedFeed(parsed) else {
      completion(failure("Ключ или адрес обновления не соответствует установленной сборке")); return
    }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      updateLock = open(directory.appendingPathComponent("install.lock").path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
      guard updateLock >= 0, flock(updateLock, LOCK_EX | LOCK_NB) == 0 else { unlock(); throw failure("Другое окно уже обновляет приложение") }
      for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where file.lastPathComponent.hasPrefix("message-") {
        try FileManager.default.removeItem(at: file)
      }
      finish = completion; feed = url; wantedVersion = version; self.packageURL = packageURL
      // Sparkle monitors one running instance. Close peers before it registers
      // that instance, otherwise a departing peer can trigger installation on quit.
      prepare { [weak self] choice in
        guard let self, choice == .install, self.finish != nil else { return }
        do {
          let instance = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
          self.updater = instance
          try instance.start()
          instance.checkForUpdates()
        } catch { self.end(error) }
      }
    } catch { end(error) }
  }
  func feedURLString(for updater: SPUUpdater) -> String? { feed }
  private func post(_ action: String, token: String, extra: [String: String] = [:]) {
    var values = extra; values["action"] = action; values["token"] = token; values["pid"] = String(getpid()); values["profile"] = profile
    do {
      let data = try JSONSerialization.data(withJSONObject: values)
      try data.write(to: directory.appendingPathComponent("message-" + token + "-" + String(getpid()) + "-" + action + ".json"), options: .atomic)
    } catch { end(error) }
  }
  private func receiveMessages() {
    guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
    for file in files where file.lastPathComponent.hasPrefix("message-") && file.pathExtension == "json" {
      guard !seenMessages.contains(file.lastPathComponent), let data = try? Data(contentsOf: file), data.count <= 4096,
            let values = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { continue }
      seenMessages.insert(file.lastPathComponent)
      receive(values)
    }
  }
  private func receive(_ values: [String: String]) {
    guard let peer = Int32(values["pid"] ?? ""),
          let active = try? activeProfiles(), active[peer] == values["profile"],
          let request = values["token"], UUID(uuidString: request) != nil else { return }
    switch values["action"] {
    case "prepare":
      canExit { [weak self] ready in guard let self else { return }; if ready { self.preparedToken = request }; self.post("reply", token: request, extra: ["ready": ready ? "yes" : "no"]) }
    case "reply":
      if request == token && expected.contains(peer) { replies[peer] = (values["ready"] == "yes", values["profile"] ?? "default") }
    case "commit":
      if request == preparedToken && peer != getpid() { canExit { ready in if ready { NSApp.terminate(nil) } } }
    default: break
    }
  }
  private func emit(_ stage: String, _ value: Double) { if finish != nil { progress(stage, value) } }
  private func prepare(_ reply: @escaping (SPUUserUpdateChoice) -> Void) {
    guard finish != nil else { reply(.skip); return }
    emit("installing", 1)
    do { expected = Set(try activeProfiles().keys) }
    catch { reply(.skip); end(error); return }
    expected.insert(getpid()); replies = [:]; token = UUID().uuidString
    post("prepare", token: token)
    canExit { [weak self] ready in guard let self else { return }; self.replies[getpid()] = (ready, self.profile) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
      guard let self else { return }
      guard self.finish != nil else { reply(.skip); return }
      guard self.expected.allSatisfy({ self.replies[$0]?.0 == true }) else {
        reply(.skip); self.end(self.failure("Закройте редакторы и завершите отправки во всех профилях, затем повторите обновление")); return
      }
      do {
        self.relaunchProfiles.formUnion(self.expected.compactMap { self.replies[$0]?.1 })
        let profiles = self.relaunchProfiles.sorted()
        let data = try JSONSerialization.data(withJSONObject: ["profiles": profiles, "created": Date().timeIntervalSince1970, "version": self.wantedVersion])
        try data.write(to: self.directory.appendingPathComponent("relaunch.json"), options: .atomic)
      } catch { reply(.skip); self.end(error); return }
      self.post("commit", token: self.token)
      self.waitForPeers(reply, attempts: 20)
    }
  }
  private func waitForPeers(_ reply: @escaping (SPUUserUpdateChoice) -> Void, attempts: Int) {
    guard finish != nil else { reply(.skip); return }
    let others: [Int32]
    do { others = try activeProfiles().keys.filter { $0 != getpid() } }
    catch { reply(.skip); end(error); return }
    if others.isEmpty {
      canExit { [weak self] ready in
        guard let self else { return }
        if ready { self.emit("installing", 1); reply(.install) }
        else { reply(.skip); self.end(self.failure("Открыт редактор сообщения")) }
      }
    } else if attempts > 0 {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.waitForPeers(reply, attempts: attempts - 1) }
    } else { reply(.skip); end(failure("Другие профили не завершились; обновление отложено")) }
  }
  // Sparkle restarts without --profile. Restore the original set of profile windows.
  static func installInProgress() -> Bool {
    let path = Bundle.main.bundleURL.standardizedFileURL.path
    let hash = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let file = support.appendingPathComponent("FFIDO/Updates/" + hash + "/install.lock")
    let fd = open(file.path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
    if fd < 0 { return false }
    defer { close(fd) }
    return flock(fd, LOCK_EX | LOCK_NB) != 0
  }
  private static var coordinationDirectory: URL {
    let path = Bundle.main.bundleURL.standardizedFileURL.path
    let hash = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return support.appendingPathComponent("FFIDO/Updates/" + hash)
  }
  private static func launchRecord(_ file: URL) -> [String] {
    guard let raw = try? Data(contentsOf: file), raw.count < 16384,
          let value = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
          value["version"] as? String == Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
          let created = value["created"] as? Double, (0..<600).contains(Date().timeIntervalSince1970 - created),
          let profiles = value["profiles"] as? [String], profiles.count <= 64,
          profiles.allSatisfy({ (try? LaunchProfile(arguments: ["--profile", $0])) != nil }) else { return [] }
    return profiles
  }
  private static func writeLaunchRecord(_ profiles: [String], file: URL) throws {
    let record: [String: Any] = ["profiles": profiles, "created": Date().timeIntervalSince1970,
                               "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""]
    try JSONSerialization.data(withJSONObject: record).write(to: file, options: .atomic)
  }
  // NSWorkspace ignores arguments from sandboxed callers. Assign restored
  // profiles through a short-lived, locked queue in the app's private container.
  static func openProfiles(_ profiles: [String]) throws {
    guard !profiles.isEmpty else { return }
    let directory = coordinationDirectory
    let fd = open(directory.appendingPathComponent("launch.lock").path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { throw ProfileError.storage }
    defer { close(fd) }
    guard flock(fd, LOCK_EX) == 0 else { throw ProfileError.storage }
    let file = directory.appendingPathComponent("launch-queue.json")
    try writeLaunchRecord(launchRecord(file) + profiles, file: file)
    flock(fd, LOCK_UN)
    for _ in profiles {
      let config = NSWorkspace.OpenConfiguration(); config.createsNewApplicationInstance = true
      NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, error in
        if let error {
          DispatchQueue.main.async {
            let alert = NSAlert(); alert.messageText = "Не удалось восстановить окно профиля"
            alert.informativeText = "Откройте профиль вручную. " + error.localizedDescription
            alert.runModal()
          }
        }
      }
    }
  }
  static func restoration() -> [String] {
    let directory = coordinationDirectory
    let fd = open(directory.appendingPathComponent("launch.lock").path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { return [] }
    defer { close(fd) }
    guard flock(fd, LOCK_EX) == 0 else { return [] }
    let queue = directory.appendingPathComponent("launch-queue.json")
    let pending = launchRecord(queue)
    if let first = pending.first {
      do { try writeLaunchRecord(Array(pending.dropFirst()), file: queue); return [first] }
      catch { return [] }
    }
    let file = directory.appendingPathComponent("relaunch.json")
    let profiles = launchRecord(file)
    if !profiles.isEmpty { try? FileManager.default.removeItem(at: file) }
    return Array(Set(profiles)).sorted()
  }
  func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) { reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false)) }
  func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { self.cancellation = cancellation }
  func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
    if finish != nil && appcastItem.versionString == wantedVersion && appcastItem.fileURL?.absoluteString == packageURL {
      // A resumed installation skips showReady; coordinate before accepting it.
      if state.stage == .notDownloaded { reply(.install) } else { prepare(reply) }
    }
    else { reply(.skip); end(failure("Версия appcast не совпадает с проверенным выпуском")) }
  }
  func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
  func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
  func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { acknowledgement(); end(error) }
  func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { acknowledgement(); end(error) }
  func showDownloadInitiated(cancellation: @escaping () -> Void) { self.cancellation = cancellation; downloaded = 0; total = 0; emit("downloading", 0) }
  func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { total = expectedContentLength }
  func showDownloadDidReceiveData(ofLength length: UInt64) { downloaded += length; emit("downloading", total > 0 ? Double(downloaded) / Double(total) : 0) }
  func showDownloadDidStartExtractingUpdate() { emit("extracting", 1) }
  func showExtractionReceivedProgress(_ progress: Double) {}
  func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { prepare(reply) }
  func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) { emit("installing", 1) }
  func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement(); end(nil) }
  func dismissUpdateInstallation() {}
}
