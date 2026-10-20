#include "service/point_mail.hpp"

#include <fnmatch.h>

#include <algorithm>
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
std::expected<void, domain::ApiError> ValidatePointMail(const AppConfig& config, const HptConfiguration& hpt) {
  if (!config.point_mail.enabled)
    return {};
  const auto failure = [] { return std::unexpected(domain::ApiError::Server("Unsafe point mail configuration")); };
  const auto& transport = hpt.transport;
  if (!transport.available || !transport.keep_transit || transport.pack_on_scan ||
      config.ftn.coordination_lock.empty() || config.point_mail.points.empty() ||
      config.point_mail.ingress_areas.empty())
    return failure();
  std::set<std::string> own(transport.own_addresses.begin(), transport.own_addresses.end()), names, paths;
  auto netmail = [&](const std::string& name, bool ingress) {
    const auto found = std::find_if(hpt.private_areas.begin(), hpt.private_areas.end(),
                                    [&](const auto& area) { return Fold(area.name) == Fold(name); });
    if (found == hpt.private_areas.end() || found->kind != AreaKind::kNetmail || found->msgbase_type != "JAM" ||
        !found->aka || !own.contains(*found->aka) || found->aka->find('.') != std::string::npos)
      return false;
    const auto policy = std::find_if(transport.netmail.begin(), transport.netmail.end(),
                                     [&](const auto& p) { return Fold(p.name) == Fold(name); });
    return policy != transport.netmail.end() && (!ingress || policy->dupe_check_off);
  };
  if (!netmail(config.point_mail.egress_area, false))
    return failure();
  names.insert(Fold(config.point_mail.egress_area));
  for (const auto& name : config.point_mail.ingress_areas)
    if (!names.insert(Fold(name)).second || !netmail(name, true))
      return failure();
  const auto root = std::filesystem::absolute(config.ftn.jam_base_path).lexically_normal();
  for (const auto& area : hpt.private_areas)
    paths.insert(std::filesystem::absolute(area.filename).lexically_normal().string());
  for (const auto& area : hpt.echoes)
    paths.insert(std::filesystem::absolute(area.filename).lexically_normal().string());
  std::set<std::string> addresses;
  for (const auto& point : config.point_mail.points) {
    auto canonical = domain::CanonicalFtnAddress(point.address);
    const auto dot = point.address.find('.');
    if (!canonical || *canonical != point.address || dot == std::string::npos || own.contains(point.address) ||
        !addresses.insert(point.address).second || !hpt.credentials.contains(point.address) ||
        hpt.credentials.at(point.address).empty())
      return failure();
    const auto boss = point.address.substr(0, dot);
    const auto link = transport.link_akas.find(point.address);
    if (!own.contains(boss) || link == transport.link_akas.end() || link->second != boss)
      return failure();
    auto route = std::find_if(transport.routes.begin(), transport.routes.end(), [&](const auto& r) {
      return r.mail && fnmatch(r.pattern.c_str(), point.address.c_str(), 0) == 0;
    });
    if (route == transport.routes.end() || !route->nopack || route->pattern != point.address)
      return failure();
    if (point.jam_base.empty() || point.jam_base.is_absolute())
      return failure();
    for (const auto& part : point.jam_base)
      if (part == ".." || part == "." || part.empty())
        return failure();
    if (!paths.insert((root / point.jam_base).lexically_normal().string()).second)
      return failure();
  }
  if (std::none_of(transport.routes.begin(), transport.routes.end(),
                   [](const auto& route) { return route.mail && !route.nopack; }))
    return failure();
  return {};
}
}  // namespace fidoback::service
