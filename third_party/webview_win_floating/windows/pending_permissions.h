#pragma once

#include <functional>
#include <map>
#include <utility>

// Owns completion of native permission deferrals, independently of COM. Erase
// before invoking so duplicate/late replies and reentrant callbacks are safe.
class PendingPermissions {
 public:
  using Complete = std::function<void(bool)>;
  PendingPermissions() = default;
  PendingPermissions(const PendingPermissions&) = delete;
  PendingPermissions& operator=(const PendingPermissions&) = delete;
  ~PendingPermissions() { Close(); }

  int Add(Complete complete) {
    if (closed_) {
      complete(false);
      return 0;
    }
    const int id = ++last_id_;
    pending_.emplace(id, std::move(complete));
    return id;
  }

  void Respond(int id, bool granted) {
    const auto found = pending_.find(id);
    if (found == pending_.end()) return;
    auto complete = std::move(found->second);
    pending_.erase(found);
    complete(granted);
  }

  void CancelAll() {
    auto previous = std::move(pending_);
    pending_.clear();
    for (auto& entry : previous) entry.second(false);
  }

  void Close() {
    closed_ = true;
    CancelAll();
  }

 private:
  int last_id_ = 0;
  bool closed_ = false;
  std::map<int, Complete> pending_;
};
