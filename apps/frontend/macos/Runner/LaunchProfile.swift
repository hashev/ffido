import Foundation
import Darwin

struct LaunchProfile {
  let id: String

  init(arguments: [String]) throws {
    var selected: String?
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      if argument == "--profile" || argument.hasPrefix("--profile=") {
        guard selected == nil else { throw ProfileError.invalid }
        if argument == "--profile" {
          index += 1
          guard index < arguments.count else { throw ProfileError.invalid }
          selected = arguments[index]
        } else {
          selected = String(argument.dropFirst("--profile=".count))
        }
      }
      index += 1
    }
    let value = selected ?? "default"
    let bytes = Array(value.utf8)
    func alphanumeric(_ byte: UInt8) -> Bool {
      return (97...122).contains(byte) || (48...57).contains(byte)
    }
    guard (1...32).contains(bytes.count), let first = bytes.first, alphanumeric(first),
          bytes.allSatisfy({ alphanumeric($0) || $0 == 95 || $0 == 45 })
      else { throw ProfileError.invalid }
    id = value
  }
}

enum ProfileError: LocalizedError {
  case invalid, busy(String), storage
  var errorDescription: String? {
    switch self {
    case .invalid: return "Неверный профиль. Используйте --profile point1: 1–32 строчных латинских букв, цифр, _ или -, первый символ — буква или цифра."
    case .busy(let id): return "Профиль \(id) уже открыт. Выберите другой профиль или закройте его первое окно."
    case .storage: return "Не удалось заблокировать хранилище профиля. Проверьте доступ к Application Support."
    }
  }
}

final class ProfileLease {
  private let descriptor: Int32
  init(directory: URL, profile: LaunchProfile) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                          attributes: [.posixPermissions: 0o700])
    descriptor = open(directory.appendingPathComponent(profile.id + ".lock").path,
                      O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
    guard descriptor >= 0 else { throw ProfileError.storage }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      let busy = errno == EWOULDBLOCK
      close(descriptor)
      throw busy ? ProfileError.busy(profile.id) : ProfileError.storage
    }
    // A locked descriptor is authoritative; GUI process inventories omit some
    // directly launched --profile instances. Keep PID metadata on this inode.
    let record: [String: Any] = ["pid": getpid(), "profile": profile.id,
                               "bundle": Bundle.main.bundleURL.standardizedFileURL.path]
    guard let data = try? JSONSerialization.data(withJSONObject: record),
          ftruncate(descriptor, 0) == 0, lseek(descriptor, 0, SEEK_SET) == 0,
          data.withUnsafeBytes({ write(descriptor, $0.baseAddress, data.count) }) == data.count else {
      close(descriptor); throw ProfileError.storage
    }
  }
  deinit { close(descriptor) }
}
