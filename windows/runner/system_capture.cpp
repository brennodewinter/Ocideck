#include "system_capture.h"

#include <audioclient.h>
#include <mmdeviceapi.h>

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstring>
#include <memory>
#include <string>
#include <thread>
#include <vector>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr int kPcmMessage = 1;
constexpr int kEndedMessage = 2;

HWND g_window = nullptr;
std::unique_ptr<flutter::EventSink<EncodableValue>> g_sink;
std::unique_ptr<flutter::MethodChannel<EncodableValue>> g_methods;
std::unique_ptr<flutter::EventChannel<EncodableValue>> g_channel;
std::thread g_thread;
HANDLE g_stop = nullptr;
bool g_running = false;

void PostEnded(const char* cause) {
  if (g_window == nullptr) return;
  auto* text = new std::string(cause);
  PostMessage(g_window, kSystemCaptureMessage, kEndedMessage,
              reinterpret_cast<LPARAM>(text));
}

void PostPcm(std::vector<uint8_t> bytes) {
  if (g_window == nullptr || bytes.empty()) return;
  auto* owned = new std::vector<uint8_t>(std::move(bytes));
  PostMessage(g_window, kSystemCaptureMessage, kPcmMessage,
              reinterpret_cast<LPARAM>(owned));
}

void AppendS16(const BYTE* data, UINT32 frames, const WAVEFORMATEX* format,
               std::vector<uint8_t>* out) {
  const UINT32 channels = format->nChannels;
  bool is_float = format->wFormatTag == WAVE_FORMAT_IEEE_FLOAT;
  WORD bits = format->wBitsPerSample;
  if (format->wFormatTag == WAVE_FORMAT_EXTENSIBLE && format->cbSize >= 22) {
    const auto* ext = reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(format);
    if (ext->Samples.wValidBitsPerSample != 0) {
      bits = ext->Samples.wValidBitsPerSample;
    }
    static const GUID kIeeeFloat = {
        0x00000003, 0x0000, 0x0010,
        {0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71}};
    is_float = ext->SubFormat == kIeeeFloat;
  }
  const size_t before = out->size();
  out->resize(before + static_cast<size_t>(frames) * channels * 2);
  auto* dst = reinterpret_cast<int16_t*>(out->data() + before);
  if (is_float && bits == 32) {
    const auto* src = reinterpret_cast<const float*>(data);
    for (UINT32 i = 0; i < frames * channels; ++i) {
      float s = src[i];
      if (s > 1) s = 1;
      if (s < -1) s = -1;
      dst[i] = static_cast<int16_t>(s * 32767);
    }
    return;
  }
  if (!is_float && bits == 16) {
    memcpy(dst, data, static_cast<size_t>(frames) * channels * 2);
    return;
  }
  memset(dst, 0, static_cast<size_t>(frames) * channels * 2);
}

struct CaptureArgs {
  HANDLE ready = nullptr;
  HRESULT hr = E_FAIL;
  int rate = 0;
  int channels = 0;
};

void CaptureMain(CaptureArgs* args) {
  const HRESULT init = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  IMMDeviceEnumerator* enumerator = nullptr;
  IMMDevice* device = nullptr;
  IAudioClient* client = nullptr;
  IAudioCaptureClient* capture = nullptr;
  WAVEFORMATEX* mix = nullptr;
  HANDLE audio_event = CreateEvent(nullptr, FALSE, FALSE, nullptr);

  class Notify : public IMMNotificationClient {
   public:
    STDMETHODIMP QueryInterface(REFIID riid, void** object) override {
      if (riid == __uuidof(IUnknown) ||
          riid == __uuidof(IMMNotificationClient)) {
        *object = this;
        return S_OK;
      }
      *object = nullptr;
      return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return 1; }
    STDMETHODIMP_(ULONG) Release() override { return 1; }
    STDMETHODIMP OnDeviceStateChanged(LPCWSTR, DWORD) override { return S_OK; }
    STDMETHODIMP OnDeviceAdded(LPCWSTR) override { return S_OK; }
    STDMETHODIMP OnDeviceRemoved(LPCWSTR) override { return S_OK; }
    STDMETHODIMP OnDefaultDeviceChanged(EDataFlow flow, ERole,
                                        LPCWSTR) override {
      // Een nieuw standaard-uitvoerapparaat volgen we niet. Stoppen.
      if (flow == eRender) {
        PostEnded("sourceLost");
        SetEvent(g_stop);
      }
      return S_OK;
    }
    STDMETHODIMP OnPropertyValueChanged(LPCWSTR, const PROPERTYKEY) override {
      return S_OK;
    }
  };

  HRESULT hr = CoCreateInstance(
      __uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
      __uuidof(IMMDeviceEnumerator), reinterpret_cast<void**>(&enumerator));
  Notify* notify = nullptr;
  if (SUCCEEDED(hr)) {
    hr = enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device);
  }
  if (SUCCEEDED(hr) && device != nullptr) {
    notify = new Notify();
    enumerator->RegisterEndpointNotificationCallback(notify);
    hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                          reinterpret_cast<void**>(&client));
  }
  if (SUCCEEDED(hr)) hr = client->GetMixFormat(&mix);
  if (SUCCEEDED(hr)) {
    hr = client->Initialize(
        AUDCLNT_SHAREMODE_SHARED,
        AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
        1000000, 0, mix, nullptr);
  }
  if (SUCCEEDED(hr)) hr = client->SetEventHandle(audio_event);
  if (SUCCEEDED(hr)) {
    hr = client->GetService(__uuidof(IAudioCaptureClient),
                            reinterpret_cast<void**>(&capture));
  }
  if (SUCCEEDED(hr)) hr = client->Start();
  args->hr = hr;
  if (SUCCEEDED(hr) && mix != nullptr) {
    args->rate = mix->nSamplesPerSec;
    args->channels = mix->nChannels;
  }
  SetEvent(args->ready);
  if (SUCCEEDED(hr)) {
    std::vector<uint8_t> pending;
    const size_t flush_at =
        static_cast<size_t>(args->rate > 0 ? args->rate : 1) * args->channels;
    while (WaitForSingleObject(g_stop, 0) != WAIT_OBJECT_0) {
      WaitForSingleObject(audio_event, 200);
      if (WaitForSingleObject(g_stop, 0) == WAIT_OBJECT_0) break;
      UINT32 packet = 0;
      while (SUCCEEDED(capture->GetNextPacketSize(&packet)) && packet > 0) {
        BYTE* data = nullptr;
        UINT32 frames = 0;
        DWORD flags = 0;
        const HRESULT got =
            capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr);
        if (got == AUDCLNT_E_DEVICE_INVALIDATED) {
          PostEnded("sourceLost");
          SetEvent(g_stop);
          break;
        }
        if (FAILED(got)) break;
        if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0 || data == nullptr) {
          std::vector<BYTE> zeros(
              static_cast<size_t>(frames) * mix->nBlockAlign, 0);
          AppendS16(zeros.data(), frames, mix, &pending);
        } else {
          AppendS16(data, frames, mix, &pending);
        }
        capture->ReleaseBuffer(frames);
        if (pending.size() >= flush_at) {
          PostPcm(std::move(pending));
          pending.clear();
        }
        capture->GetNextPacketSize(&packet);
      }
    }
    if (!pending.empty()) PostPcm(std::move(pending));
    client->Stop();
  }
  if (notify != nullptr && enumerator != nullptr) {
    enumerator->UnregisterEndpointNotificationCallback(notify);
    delete notify;
  }
  if (mix != nullptr) CoTaskMemFree(mix);
  if (capture != nullptr) capture->Release();
  if (client != nullptr) client->Release();
  if (device != nullptr) device->Release();
  if (enumerator != nullptr) enumerator->Release();
  if (audio_event != nullptr) CloseHandle(audio_event);
  if (SUCCEEDED(init)) CoUninitialize();
}

void Fail(std::unique_ptr<flutter::MethodResult<EncodableValue>> result,
          const char* code, const char* message) {
  result->Error(code, message);
}

void HandleStop() {
  if (g_stop != nullptr) SetEvent(g_stop);
  if (g_thread.joinable()) g_thread.join();
  g_running = false;
}

void HandleOpen(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (g_running) {
    Fail(std::move(result), "sourceUnavailable", "systeemgeluid is al open");
    return;
  }
  if (g_stop == nullptr) g_stop = CreateEvent(nullptr, TRUE, FALSE, nullptr);
  ResetEvent(g_stop);
  auto* args = new CaptureArgs();
  args->ready = CreateEvent(nullptr, TRUE, FALSE, nullptr);
  g_thread = std::thread(CaptureMain, args);
  WaitForSingleObject(args->ready, 5000);
  const HRESULT hr = args->hr;
  const int rate = args->rate;
  const int channels = args->channels;
  CloseHandle(args->ready);
  delete args;
  if (FAILED(hr) || rate <= 0 || channels <= 0) {
    SetEvent(g_stop);
    if (g_thread.joinable()) g_thread.join();
    const char* code =
        hr == E_ACCESSDENIED ? "permissionDenied" : "sourceUnavailable";
    Fail(std::move(result), code, "systeemgeluid openen mislukt");
    return;
  }
  g_running = true;
  EncodableMap ok;
  ok[EncodableValue("sampleRate")] = EncodableValue(rate);
  ok[EncodableValue("channels")] = EncodableValue(channels);
  result->Success(EncodableValue(ok));
}

class SystemEvents : public flutter::StreamHandler<EncodableValue> {
 protected:
  std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> OnListenInternal(
      const EncodableValue*,
      std::unique_ptr<flutter::EventSink<EncodableValue>>&& events) override {
    g_sink = std::move(events);
    return nullptr;
  }
  std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> OnCancelInternal(
      const EncodableValue*) override {
    g_sink.reset();
    return nullptr;
  }
};

}  // namespace

void RegisterSystemCapture(flutter::BinaryMessenger* messenger, HWND window) {
  g_window = window;
  g_methods = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "ocideck/system_capture",
      &flutter::StandardMethodCodec::GetInstance());
  g_channel = std::make_unique<flutter::EventChannel<EncodableValue>>(
      messenger, "ocideck/system_capture_pcm",
      &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetStreamHandler(
      std::unique_ptr<flutter::StreamHandler<EncodableValue>>(
          std::make_unique<SystemEvents>()));
  g_methods->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() == "describe") {
          EncodableMap body;
          body[EncodableValue("availability")] =
              EncodableValue("tryAfterPermission");
          body[EncodableValue("inputs")] = EncodableValue(flutter::EncodableList());
          result->Success(EncodableValue(body));
        } else if (call.method_name() == "open") {
          HandleOpen(std::move(result));
        } else if (call.method_name() == "stop") {
          HandleStop();
          result->Success();
        } else if (call.method_name() == "freeBytes") {
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

void ShutdownSystemCapture() {
  HandleStop();
  g_sink.reset();
  g_methods.reset();
  g_channel.reset();
  if (g_stop != nullptr) {
    CloseHandle(g_stop);
    g_stop = nullptr;
  }
  g_window = nullptr;
}

void HandleSystemCaptureMessage(WPARAM wparam, LPARAM lparam) {
  if (wparam == kPcmMessage) {
    auto* bytes = reinterpret_cast<std::vector<uint8_t>*>(lparam);
    if (g_sink != nullptr && bytes != nullptr) {
      g_sink->Success(EncodableValue(*bytes));
    }
    delete bytes;
    return;
  }
  if (wparam == kEndedMessage) {
    auto* cause = reinterpret_cast<std::string*>(lparam);
    if (g_sink != nullptr && cause != nullptr) {
      EncodableMap event;
      event[EncodableValue("event")] = EncodableValue("ended");
      event[EncodableValue("cause")] = EncodableValue(*cause);
      g_sink->Success(EncodableValue(event));
    }
    delete cause;
  }
}
