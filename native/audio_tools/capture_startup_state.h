// Copyright Stichting LibreKAT. EUPL-1.2.
#ifndef OCIDECK_CAPTURE_STARTUP_STATE_H_
#define OCIDECK_CAPTURE_STARTUP_STATE_H_

#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <optional>

namespace ocideck {

struct CaptureStartupResult {
  int32_t status;
  int sample_rate;
  int channels;
};

// UI en worker houden elk gedeeld eigenaarschap. Een verlopen wait geeft
// geen recht om de nog door de worker gebruikte starttoestand vrij te geven.
class CaptureStartupState {
 public:
  void Publish(CaptureStartupResult result) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (ready_) return;
      result_ = result;
      ready_ = true;
    }
    ready_changed_.notify_all();
  }

  std::optional<CaptureStartupResult> WaitFor(
      std::chrono::milliseconds timeout) {
    std::unique_lock<std::mutex> lock(mutex_);
    if (!ready_changed_.wait_for(lock, timeout, [this] { return ready_; })) {
      return std::nullopt;
    }
    return result_;
  }

 private:
  std::mutex mutex_;
  std::condition_variable ready_changed_;
  bool ready_ = false;
  CaptureStartupResult result_{};
};

}  // namespace ocideck
#endif  // OCIDECK_CAPTURE_STARTUP_STATE_H_
