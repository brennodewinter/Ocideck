// OciDeck modification, EUPL-1.2; see MODIFICATIONS.md.
#ifndef FLUTTER_WEBRTC_AUDIO_CAPTURE_H_
#define FLUTTER_WEBRTC_AUDIO_CAPTURE_H_
#include "flutter_common.h"
#include "rtc_audio_track.h"
#include <atomic>

namespace flutter_webrtc_plugin {
// One decoded track, never an endpoint mix. Platform messages are bounded and
// carry only owned bytes; audio callbacks never touch Flutter's messenger.
class FlutterAudioCapture final : public libwebrtc::AudioTrackSink {
 public:
  FlutterAudioCapture(libwebrtc::scoped_refptr<libwebrtc::RTCAudioTrack> track,
                      BinaryMessenger* messenger, TaskRunner* runner, int id);
  ~FlutterAudioCapture() override;
  void OnData(const void* data, int bits, int rate, size_t channels,
              size_t frames) override;
 private:
  struct State {
    std::atomic<bool> alive{true};
    std::atomic<bool> failed{false};
    std::atomic<int> pending{0};
    std::unique_ptr<EventChannelProxy> channel;
  };
  libwebrtc::scoped_refptr<libwebrtc::RTCAudioTrack> track_;
  TaskRunner* runner_;
  std::shared_ptr<State> state_;
};
}  // namespace flutter_webrtc_plugin
#endif
