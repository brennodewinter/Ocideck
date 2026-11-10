// Copyright Stichting LibreKAT. EUPL-1.2.
#include <gst/gst.h>
#include <pulse/pulseaudio.h>
#include <pulse/simple.h>
#include <pulse/error.h>
#include <cstdio>
#include <cstring>
#include <string>
#include <unistd.h>
#include <sys/time.h>
#include <atomic>

namespace {
struct Sources { pa_mainloop* loop; bool success = false; };
void Source(pa_context*, const pa_source_info* info, int end, void* data) {
  auto* state = static_cast<Sources*>(data);
  if (end != 0) {
    state->success = end > 0;
    pa_mainloop_quit(state->loop, end > 0 ? 0 : 1);
    return;
  }
  if (!info || !info->name) return;
  const char* bus = pa_proplist_gets(info->proplist, "device.bus");
  std::printf("Source #%u\nName: %s\nDescription: %s\ndevice.bus = %s\n",
      info->index, info->name, info->description ? info->description : info->name,
      bus ? bus : "unknown");
}
void Context(pa_context* context, void* data) {
  auto* state = static_cast<Sources*>(data);
  switch (pa_context_get_state(context)) {
    case PA_CONTEXT_READY: {
      auto* operation = pa_context_get_source_info_list(context, Source, data);
      if (operation) pa_operation_unref(operation);
      else pa_mainloop_quit(state->loop, 1);
      break;
    }
    case PA_CONTEXT_FAILED:
    case PA_CONTEXT_TERMINATED: pa_mainloop_quit(state->loop, 1); break;
    default: break;
  }
}
int ListSources() {
  auto* loop = pa_mainloop_new();
  if (!loop) return 1;
  Sources state{loop};
  auto* context = pa_context_new(pa_mainloop_get_api(loop), "OciDeck source list");
  if (!context) { pa_mainloop_free(loop); return 1; }
  pa_context_set_state_callback(context, Context, &state);
  timeval deadline;
  gettimeofday(&deadline, nullptr);
  deadline.tv_sec += 2;
  auto* timer = pa_mainloop_get_api(loop)->time_new(pa_mainloop_get_api(loop), &deadline,
      +[](pa_mainloop_api*, pa_time_event*, const timeval*, void* data) {
        pa_mainloop_quit(static_cast<pa_mainloop*>(data), 1);
      }, loop);
  int status = 1;
  if (pa_context_connect(context, nullptr, PA_CONTEXT_NOAUTOSPAWN, nullptr) == 0)
    pa_mainloop_run(loop, &status);
  if (timer) pa_mainloop_get_api(loop)->time_free(timer);
  pa_context_disconnect(context);
  pa_context_unref(context);
  pa_mainloop_free(loop);
  return state.success && status == 0 ? 0 : 1;
}
int Capture(const char* device) {
  const pa_sample_spec format{PA_SAMPLE_S16LE, 48000, 2};
  const pa_buffer_attr buffer{UINT32_MAX, UINT32_MAX, UINT32_MAX, UINT32_MAX, 1920};
  int error = 0;
  pa_simple* stream = pa_simple_new(nullptr, "OciDeck", PA_STREAM_RECORD,
      device, "Recording", &format, nullptr, &buffer, &error);
  if (!stream) return 1;
  unsigned char pcm[1920];
  int status = 0;
  while (true) {
    if (pa_simple_read(stream, pcm, sizeof(pcm), &error) < 0) { status = 1; break; }
    if (std::fwrite(pcm, 1, sizeof(pcm), stdout) != sizeof(pcm) ||
        std::fflush(stdout) != 0) { status = 1; break; }
  }
  pa_simple_free(stream);
  return status;
}
int Decode(const char* input, const char* output) {
  // The installed Flatpak can carry codec plugins absent from its runtime.
  char executable[4096];
  const auto length = readlink("/proc/self/exe", executable, sizeof(executable) - 1);
  if (length > 0) {
    executable[length] = '\0';
    std::string directory(executable);
    directory = directory.substr(0, directory.find_last_of('/'));
    const auto plugins = directory + "/lib/gstreamer-1.0";
    g_setenv("GST_PLUGIN_PATH_1_0", plugins.c_str(), TRUE);
  }
  // One fixed pipeline: user paths are properties, never pipeline source.
  gst_init(nullptr, nullptr);
  GError* error = nullptr;
  auto* pipeline = gst_parse_launch(
      "filesrc name=input ! decodebin name=decoder ! audioconvert name=convert ! audioresample ! "
      "audio/x-raw,format=S16LE,rate=16000,channels=1 ! wavenc ! filesink name=output",
      &error);
  if (error || !pipeline) {
    if (error) g_error_free(error);
    if (pipeline) gst_object_unref(pipeline);
    return 1;
  }
  auto* source = gst_bin_get_by_name(GST_BIN(pipeline), "input");
  auto* sink = gst_bin_get_by_name(GST_BIN(pipeline), "output");
  g_object_set(source, "location", input, nullptr);
  g_object_set(sink, "location", output, nullptr);
  gst_object_unref(source);
  gst_object_unref(sink);
  struct DecodeState { GstElement* pipeline; std::atomic<bool> no_audio{false}; };
  DecodeState state{pipeline};
  auto* decoder = gst_bin_get_by_name(GST_BIN(pipeline), "decoder");
  g_signal_connect(decoder, "no-more-pads", G_CALLBACK(+[](GstElement* element, gpointer data) {
    auto* state = static_cast<DecodeState*>(data);
    auto* convert = gst_bin_get_by_name(GST_BIN(state->pipeline), "convert");
    auto* sink_pad = gst_element_get_static_pad(convert, "sink");
    if (!gst_pad_is_linked(sink_pad)) {
      state->no_audio = true;
      GST_ELEMENT_ERROR(element, STREAM, TYPE_NOT_FOUND, ("No audio track"), (nullptr));
    }
    gst_object_unref(sink_pad);
    gst_object_unref(convert);
  }), &state);
  gst_object_unref(decoder);
  auto* convert = gst_bin_get_by_name(GST_BIN(pipeline), "convert");
  auto* audio_pad = gst_element_get_static_pad(convert, "src");
  uint64_t bytes = 0;
  gst_pad_add_probe(audio_pad, GST_PAD_PROBE_TYPE_BUFFER,
      +[](GstPad* pad, GstPadProbeInfo* info, gpointer data) -> GstPadProbeReturn {
        auto* bytes = static_cast<uint64_t*>(data);
        *bytes += gst_buffer_get_size(GST_PAD_PROBE_INFO_BUFFER(info));
        if (*bytes > 0x7fffffffU - 44) {
          auto* parent = gst_pad_get_parent_element(pad);
          GST_ELEMENT_ERROR(parent, RESOURCE, NO_SPACE_LEFT, ("Decoded audio exceeds limit"), (nullptr));
          gst_object_unref(parent);
          return GST_PAD_PROBE_DROP;
        }
        return GST_PAD_PROBE_OK;
      }, &bytes, nullptr);
  gst_object_unref(audio_pad);
  gst_object_unref(convert);
  auto* bus = gst_element_get_bus(pipeline);
  const auto changed = gst_element_set_state(pipeline, GST_STATE_PLAYING);
  auto* message = changed == GST_STATE_CHANGE_FAILURE ? nullptr :
      gst_bus_timed_pop_filtered(bus, 10 * 60 * GST_SECOND,
          static_cast<GstMessageType>(GST_MESSAGE_ERROR | GST_MESSAGE_EOS));
  int status = message && GST_MESSAGE_TYPE(message) == GST_MESSAGE_EOS ? 0 : 1;
  if (message) gst_message_unref(message);
  gst_element_set_state(pipeline, GST_STATE_NULL);
  gst_object_unref(bus);
  gst_object_unref(pipeline);
  if (status) std::remove(output);
  return state.no_audio ? 3 : status;
}
}  // namespace
int main(int argc, char** argv) {
  if (argc == 2 && std::strcmp(argv[1], "--list-sources") == 0) return ListSources();
  if ((argc == 2 || argc == 3) && std::strcmp(argv[1], "--capture") == 0)
    return Capture(argc == 3 ? argv[2] : nullptr);
  if (argc == 4 && std::strcmp(argv[1], "--decode") == 0)
    return Decode(argv[2], argv[3]);
  std::fputs("usage: ocideck-audio --decode INPUT OUTPUT | --list-sources | --capture [SOURCE]\n", stderr);
  return 2;
}
