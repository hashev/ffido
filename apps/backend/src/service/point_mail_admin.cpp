#include "service/point_mail_admin.hpp"

#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>

#include <iostream>

#include "service/mail_bridge.hpp"
#include "service/point_mail.hpp"
#include "storage/coordination_lock.hpp"
#include "storage/jam_lock.hpp"
#include "storage/point_mailbox.hpp"

namespace fidoback::service {
int RunMailStage(const std::filesystem::path& configuration, const std::filesystem::path& helper,
                 std::string_view stage, int lease_fd) {
  auto config = LoadAppConfig(configuration.string());
  if (!config || !config->point_mail.enabled)
    return 1;
  auto coordination = storage::CoordinationLock::Inherit(config->ftn.coordination_lock, lease_fd);
  if (!coordination)
    return 1;
  auto hpt = LoadHptConfiguration(helper, *config);
  if (!hpt) {
    std::cerr << hpt.error().message << '\n';
    return 1;
  }
  if (!ValidatePointMail(*config, *hpt))
    return 1;
  auto metadata = storage::CreateSQLiteStore(config->database.metadata_path);
  if (!metadata->Init())
    return 1;
  auto state = metadata->ExportState();
  if (!state)
    return 1;
  if (stage == "status") {
    auto transfers = metadata->MailTransfers(false);
    auto outbox = metadata->PendingOutbox();
    auto operations = metadata->PendingOperations();
    if (!transfers || !outbox || !operations)
      return 1;
    nlohmann::json pending = nlohmann::json::array();
    for (const auto& t : *transfers)
      pending.push_back({{"source_key", t.source_key},
                         {"source_conference", t.source_conference},
                         {"source_number", t.source_number},
                         {"state", static_cast<int>(t.state)},
                         {"collision", t.collision},
                         {"duplicate", t.duplicate}});
    nlohmann::json pending_outbox = nlohmann::json::array();
    for (const auto& operation : *outbox)
      pending_outbox.push_back({{"user", operation.user},
                                {"operation", operation.id},
                                {"conference", operation.conference},
                                {"message_number", operation.plan.number},
                                {"msgid", operation.ftn_msgid},
                                {"state", operation.outbox_state}});
    std::cout << nlohmann::json{{"export_state", *state},
                                {"uncertain", *state != 0},
                                {"transfers", pending},
                                {"pending_outbox", pending_outbox},
                                {"pending_operations", operations->size()}}
                     .dump(2)
              << "\n";
    return 0;
  }
  if (stage == "export-reconciled") {
    if (*state == 0)
      return 0;
    if (*state == 1 && !metadata->SetExportState(1, 2))
      return 1;
    return metadata->SetExportState(2, 0) ? 0 : 1;
  }
  if (stage == "export-complete")
    return metadata->SetExportState(1, 0) ? 0 : 1;
  if (stage == "export-uncertain")
    return metadata->SetExportState(1, 2) ? 0 : 1;
  if (*state != 0) {
    if (*state == 1 && stage == "recover" && !metadata->SetExportState(1, 2)) {
      std::cerr << "Cannot journal uncertain HPT export; export remains blocked\n";
      return 1;
    }
    std::cerr << "HPT export outcome is uncertain; operator reconciliation required\n";
    return 1;
  }
  auto areas = CatalogAreas(*config, *hpt);
  if (!areas)
    return 1;
  auto mailboxes = storage::MailboxAreas(config->point_mail, *metadata);
  if (!mailboxes)
    return 1;
  areas->insert(areas->end(), mailboxes->begin(), mailboxes->end());
  auto opened =
      storage::JamCatalog::Build(config->ftn.jam_base_path, *areas, *coordination, config->ftn.jam_encoding_overrides);
  if (!opened)
    return 1;
  auto catalog = std::shared_ptr<storage::JamCatalog>(std::move(*opened));
  MailBridge bridge(*config, *hpt, catalog, metadata);
  if (stage == "recover")
    return bridge.Recover() ? 0 : 1;
  if (stage == "dispatch")
    return bridge.Dispatch() ? 0 : 1;
  if (stage == "export-begin") {
    if (!bridge.Dispatch())
      return 1;
    auto outbox = metadata->PendingOutbox();
    if (!outbox || !outbox->empty())
      return 1;
    return metadata->SetExportState(0, 1) ? 0 : 1;
  }
  return 2;
}
int ProvisionMailboxes(const std::filesystem::path& configuration, const std::filesystem::path& helper) {
  auto config = LoadAppConfig(configuration.string());
  if (!config || !config->point_mail.enabled)
    return 1;
  auto hpt = LoadHptConfiguration(helper, *config);
  if (!hpt) {
    std::cerr << hpt.error().message << '\n';
    return 1;
  }
  if (!ValidatePointMail(*config, *hpt))
    return 1;
  auto instance = storage::BackendInstanceLock::Acquire(config->database.metadata_path.string() + ".lock");
  if (!instance)
    return 1;
  const int fd =
      open(config->ftn.coordination_lock.c_str(), O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0600);
  if (fd < 0)
    return 1;
  struct Close {
    int fd;
    ~Close() {
      close(fd);
    }
  } lease{fd};
  struct stat info{};
  if (fstat(fd, &info) != 0 || !S_ISREG(info.st_mode) || flock(fd, LOCK_EX | LOCK_NB) != 0)
    return 1;
  auto metadata = storage::CreateSQLiteStore(config->database.metadata_path);
  if (!metadata->Init())
    return 1;
  for (const auto& point : config->point_mail.points)
    if (!storage::ProvisionMailbox(config->ftn.jam_base_path, point, *metadata))
      return 1;
  return 0;
}
}  // namespace fidoback::service
