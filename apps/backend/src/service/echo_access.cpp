#include "service/echo_access.hpp"

#include <set>
namespace fidoback::service {
namespace {
std::string Fold(std::string value) {
  for (auto& c : value)
    if (c >= 'A' && c <= 'Z')
      c += 'a' - 'A';
  return value;
}
}  // namespace
std::expected<std::shared_ptr<const EchoAccess>, domain::ApiError> EchoAccess::Build(
    const HptConfiguration& configuration, const storage::JamCatalog& catalog, const std::vector<std::string>& owners) {
  auto policy = std::shared_ptr<EchoAccess>(new EchoAccess);
  for (const auto& owner : owners) {
    auto address = domain::CanonicalFtnAddress(owner);
    if (!address || !policy->owners_.insert(*address).second || !configuration.credentials.contains(*address) ||
        configuration.credentials.at(*address).empty())
      return std::unexpected(domain::ApiError::Server("Invalid owner identity configuration"));
  }
  std::map<std::string, const HptEcho*> echoes;
  for (const auto& echo : configuration.echoes) {
    if (!echoes.emplace(Fold(echo.name), &echo).second)
      return std::unexpected(domain::ApiError::Server("Ambiguous HPT echo policy"));
  }
  std::set<std::string> names;
  for (const auto& [id, area] : catalog.areas()) {
    if (!area.config.mailbox_address.empty()) {
      auto address = domain::CanonicalFtnAddress(area.config.mailbox_address);
      if (!address || *address != area.config.mailbox_address || !configuration.credentials.contains(*address) ||
          configuration.credentials.at(*address).empty() || !area.files)
        return std::unexpected(domain::ApiError::Server("Invalid mailbox access policy"));
      policy->mailboxes_.emplace(
          id, std::pair{*address, EchoPermissions{true, area.files->writable && !area.files->role_read_only, true}});
      continue;
    }
    if (area.config.kind != AreaKind::kEcho) {
      const bool read = static_cast<bool>(area.files);
      const bool post = read && area.files->writable && !area.files->role_read_only;
      policy->private_.emplace(id, EchoPermissions{read, post, true});
      continue;
    }
    const auto name = Fold(id);
    if (!names.insert(name).second)
      return std::unexpected(domain::ApiError::Server("Ambiguous JAM echo policy"));
    auto found = echoes.find(name);
    if (found == echoes.end())
      continue;
    const auto& echo = *found->second;
    if (!echo.filename.is_absolute())
      return std::unexpected(domain::ApiError::Server("HPT and JAM echo paths disagree"));
    constexpr std::array<std::string_view, 3> extensions{".jhr", ".jdt", ".jdx"};
    for (size_t i = 0; i < extensions.size(); ++i) {
      struct stat identity{};
      if (stat((echo.filename.string() + std::string(extensions[i])).c_str(), &identity) != 0 ||
          identity.st_dev != area.files->identities[i].st_dev || identity.st_ino != area.files->identities[i].st_ino)
        return std::unexpected(domain::ApiError::Server("HPT and JAM echo paths disagree"));
    }
    policy->echoes_.emplace(id, echo.links);
    policy->owner_echoes_.emplace(id, EchoPermissions{true, area.files->writable && !area.files->role_read_only, true});
  }
  return policy;
}
std::expected<EchoPermissions, domain::ApiError> EchoAccess::Permissions(storage::IMetadataStore& metadata,
                                                                         std::string_view user,
                                                                         std::string_view conference) const {
  auto profile = metadata.GetProfile(user);
  if (!profile)
    return std::unexpected(profile.error());
  auto address = domain::CanonicalFtnAddress(profile->address);
  if (!address)
    return std::unexpected(Denied());
  auto mailbox = mailboxes_.find(conference);
  if (mailbox != mailboxes_.end())
    return mailbox->second.first == *address ? mailbox->second.second : EchoPermissions{};
  auto private_area = private_.find(conference);
  if (private_area != private_.end())
    return owners_.contains(*address) ? private_area->second : EchoPermissions{};
  auto echo = echoes_.find(conference);
  if (echo == echoes_.end())
    return EchoPermissions{};
  if (owners_.contains(*address))
    return owner_echoes_.at(echo->first);
  auto link = echo->second.find(*address);
  return link == echo->second.end() ? EchoPermissions{} : link->second;
}
}  // namespace fidoback::service
