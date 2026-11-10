// Tests the production C++ track sink: owned PCM, mute, stop and backpressure.
#include "flutter_audio_capture.h"
#include "task_runner.h"
#include <cassert>
#include <iostream>

namespace {
std::map<std::string, std::vector<EncodableValue>> received;
class Events : public EventChannelProxy {
 public:
  explicit Events(std::string name) : name_(std::move(name)) {}
  void Success(const EncodableValue& event, bool) override { received[name_].push_back(event); }
 private:
  std::string name_;
};
class Runner : public TaskRunner {
 public:
  std::vector<TaskClosure> tasks;
  void EnqueueTask(TaskClosure task) override { tasks.push_back(std::move(task)); }
  void Drain() { auto pending = std::move(tasks); tasks.clear(); for (auto& task : pending) task(); }
};
class Track : public libwebrtc::RTCAudioTrack {
 public:
  bool unmuted = true;
  libwebrtc::AudioTrackSink* sink = nullptr;
  int AddRef() const override { return ++refs_; }
  int Release() const override { return --refs_; }
  RTCTrackState state() const override { return kLive; }
  const libwebrtc::string kind() const override { return "audio"; }
  const libwebrtc::string id() const override { return "test"; }
  bool enabled() const override { return unmuted; }
  bool set_enabled(bool enabled) override { unmuted = enabled; return true; }
  void SetVolume(double) override {}
  void AddSink(libwebrtc::AudioTrackSink* value) override { assert(!sink); sink = value; }
  void RemoveSink(libwebrtc::AudioTrackSink* value) override { assert(sink == value); sink = nullptr; }
 private:
  mutable int refs_ = 0;
};
}
std::unique_ptr<EventChannelProxy> EventChannelProxy::Create(
    BinaryMessenger*, TaskRunner*, const std::string& name) {
  return std::make_unique<Events>(name);
}
int main() {
  using flutter_webrtc_plugin::FlutterAudioCapture;
  Track local, remote;
  Runner runner;
  auto capture = std::make_unique<FlutterAudioCapture>(&local, nullptr, &runner, 1);
  auto other = std::make_unique<FlutterAudioCapture>(&remote, nullptr, &runner, 2);
  int16_t pcm[] = {1000, -2000, 3000, -4000};
  local.sink->OnData(pcm, 16, 48000, 2, 2);
  remote.sink->OnData(pcm, 16, 16000, 1, 4);
  pcm[0] = 0; // callback must own its bytes before the WebRTC buffer is reused.
  runner.Drain();
  auto& one = received["FlutterWebRTC/audioTrackCapture1"];
  auto& two = received["FlutterWebRTC/audioTrackCapture2"];
  assert(one.size() == 1 && two.size() == 1);
  auto first = std::get<EncodableMap>(one[0]);
  auto bytes = findVector(first, "pcm");
  assert(bytes.size() == 8 && bytes[0] == 0xe8 && bytes[1] == 0x03);
  assert(findInt(first, "channels") == 2 && findInt(first, "sampleRate") == 48000);
  local.unmuted = false;
  local.sink->OnData(pcm, 16, 48000, 2, 2);
  assert(runner.tasks.empty());
  local.unmuted = true;
  local.sink->OnData(pcm, 16, 48000, 2, 2);
  capture.reset();
  runner.Drain();
  assert(local.sink == nullptr && one.size() == 1); // stop invalidates queued PCM
  for (int i = 0; i < 1000; ++i) remote.sink->OnData(pcm, 16, 16000, 1, 4);
  assert(runner.tasks.size() == 65); // bounded PCM plus one explicit error
  runner.Drain();
  assert(findString(std::get<EncodableMap>(two.back()), "error") == "audio_capture_backpressure");
  other.reset();
  std::cout << "track sink: owned PCM, separate sources, mute, stop, bounded queue OK\n";
}
