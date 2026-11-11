// OciDeck modification, EUPL-1.2; see MODIFICATIONS.md.
#include "flutter_audio_capture.h"
#include "task_runner.h"
#include <cstring>

namespace flutter_webrtc_plugin {
FlutterAudioCapture::FlutterAudioCapture(
    libwebrtc::scoped_refptr<libwebrtc::RTCAudioTrack> track,
    BinaryMessenger* messenger, TaskRunner* runner, int id)
    : track_(track), runner_(runner), state_(std::make_shared<State>()) {
  state_->channel = EventChannelProxy::Create(
      messenger, nullptr, "FlutterWebRTC/audioTrackCapture" + std::to_string(id));
  track_->AddSink(this);
}

FlutterAudioCapture::~FlutterAudioCapture() {
  state_->alive = false;
  track_->RemoveSink(this);
  state_->channel.reset();
}

void FlutterAudioCapture::OnData(const void* data, int bits, int rate,
                               size_t channels, size_t frames) {
  if (!state_->alive || state_->failed || !track_->enabled()) return;
  const bool valid = data != nullptr && bits == 16 && rate >= 8000 &&
      rate <= 192000 && channels > 0 && channels <= 8 &&
      frames > 0 && frames <= static_cast<size_t>(rate / 10);
  const bool overflow = state_->pending.fetch_add(1) >= 64;
  if (overflow) state_->pending.fetch_sub(1);
  EncodableMap event;
  if (!valid || overflow) {
    if (state_->failed.exchange(true)) return;
    event[EncodableValue("error")] = EncodableValue(
        overflow ? "audio_capture_backpressure" : "audio_capture_format");
  } else {
    std::vector<uint8_t> bytes(frames * channels * sizeof(int16_t));
    std::memcpy(bytes.data(), data, bytes.size());
    event[EncodableValue("pcm")] = EncodableValue(std::move(bytes));
    event[EncodableValue("sampleRate")] = EncodableValue(rate);
    event[EncodableValue("channels")] = EncodableValue(static_cast<int>(channels));
  }
  std::weak_ptr<State> weak = state_;
  // One additional error task is allowed when the PCM queue reaches its bound.
  runner_->EnqueueTask([weak, event = std::move(event), overflow]() {
    const auto state = weak.lock();
    if (!state) return;
    if (!overflow) state->pending.fetch_sub(1);
    if (state->alive && state->channel) {
      state->channel->Success(EncodableValue(event), false);
    }
  });
}
}  // namespace flutter_webrtc_plugin
