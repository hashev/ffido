#include <charconv>
#include <iostream>
#include <vector>
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif

#include "service/point_mail_admin.hpp"
#include "storage/jam_audit.hpp"
#include "storage/metadata_store.hpp"

namespace {
std::filesystem::path Helper() {
  std::filesystem::path executable;
#ifdef __APPLE__
  uint32_t size = 0;
  _NSGetExecutablePath(nullptr, &size);
  std::vector<char> buffer(size);
  if (_NSGetExecutablePath(buffer.data(), &size) != 0)
    throw std::runtime_error("Cannot locate executable");
  executable = buffer.data();
#else
  executable = std::filesystem::read_symlink("/proc/self/exe");
#endif
  return std::filesystem::canonical(executable).parent_path() / "ffido-hpt-auth";
}
}  // namespace
int main(int argc, char** argv) {
  if (argc == 2 && std::string_view(argv[1]) == "--help") {
    std::cout << "ffido-admin revoke-user DB USER_ID\nffido-admin audit-jam DB BASE COORDINATION_LOCK\nffido-admin "
                 "provision-mailboxes CONFIG\nffido-admin mail-cycle CONFIG STAGE INHERITED_LEASE_FD\n";
    return 0;
  }
  if (argc == 3 && std::string_view(argv[1]) == "provision-mailboxes") {
    try {
      const auto helper = Helper();
      const int result = fidoback::service::ProvisionMailboxes(argv[2], helper);
      if (result != 0)
        std::cerr << "Mailbox provisioning failed; existing files were not assigned\n";
      return result;
    } catch (const std::exception&) {
      std::cerr << "Mailbox provisioning failed\n";
      return 1;
    }
  }
  if (argc == 5 && std::string_view(argv[1]) == "mail-cycle") {
    int fd = -1;
    const std::string_view input = argv[4];
    auto [end, error] = std::from_chars(input.data(), input.data() + input.size(), fd);
    if (error != std::errc{} || end != input.data() + input.size())
      return 2;
    try {
      return fidoback::service::RunMailStage(argv[2], Helper(), argv[3], fd);
    } catch (const std::exception&) {
      std::cerr << "Mail cycle requires administrator attention\n";
      return 1;
    }
  }
  if (argc == 5 && std::string_view(argv[1]) == "audit-jam") {
    try {
      std::cout << fidoback::storage::AuditJam(argv[2], argv[3], argv[4]).dump(2) << "\n";
      return 0;
    } catch (const std::runtime_error& error) {
      std::cerr << "Read-only JAM audit failed; no migration was performed: " << error.what() << "\n";
      return 1;
    }
  }
  if (argc != 4 || std::string_view(argv[1]) != "revoke-user" || std::string_view(argv[3]).empty()) {
    std::cerr << "Invalid command; use --help\n";
    return 2;
  }
  auto metadata = fidoback::storage::CreateSQLiteStore(argv[2]);
  if (!metadata->Init() || !metadata->RevokeUserSessions(argv[3])) {
    std::cerr << "Session revocation failed\n";
    return 1;
  }
  return 0;
}
