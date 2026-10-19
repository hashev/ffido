#pragma once
#include <set>

#include "JamMessageBase.h"
#include "domain/error.hpp"
#include "storage/mail_transfer.hpp"

namespace fidoback::service {
enum class MailRecipient { kManaged, kBoss, kOrdinary, kTransit };
struct MailEnvelope {
  std::string origin, destination, message_id;
  MailRecipient recipient = MailRecipient::kTransit;
  storage::TokenDigest delivery_key{}, payload_hash{};
};
std::expected<MailEnvelope, domain::ApiError> InspectMail(const msgapi::JamMessage& message,
                                                          const std::set<std::string>& managed,
                                                          const std::set<std::string>& own,
                                                          const std::set<std::string>& links);
}  // namespace fidoback::service
