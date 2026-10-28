#include "mic_capture.h"

#include <audioclient.h>
#include <propkeydef.h>
#include <functiondiscoverykeys_devpkey.h>
#include <mmdeviceapi.h>

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cstring>
#include <memory>
#include <string>
#include <thread>
#include <vector>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr int kPcmMessage = 1;
constexpr int kEndedMessage = 2;

HWND g_window = nullptr;
std::unique_ptr<flutter::EventSink<EncodableValue>> g_sink;
std::thread g_thread;
HANDLE g_stop = nullptr;
bool g_running = false;

std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) return {};
  const int bytes = WideCharToMultiByte(
      CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.size()), nullptr, 0,
      nullptr, nullptr);
  std::string out(bytes, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.size()),
                      out.data(), bytes, nullptr, nullptr);
  return out;
}

std::wstring Utf8ToWide(const std::string& text) {
  if (text.empty()) return {};
  const int chars = MultiByteToWideChar(
      CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring out(chars, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()),
                      out.data(), chars);
  return out;
}

std::string ReadStringProp(IPropertyStore* store, const PROPERTYKEY& key) {
  PROPVARIANT value;
  PropVariantInit(&value);
  std::string out;
  if (SUCCEEDED(store->GetValue(key, &value)) && value.vt == VT_LPWSTR &&
      value.pwszVal != nullptr) {
    out = WideToUtf8(value.pwszVal);
  }
  PropVariantClear(&value);
  return out;
}

const char* TransportOf(const std::string& enumerator) {
  std::string upper = enumerator;
  std::transform(upper.begin(), upper.end(), upper.begin(), [](unsigned char c) {
    return static_cast<char>(std::toupper(c));
  });
  if (upper.find("USB") != std::string::npos) return "usb";
  if (upper.find("BTH") != std::string::npos ||
      upper.find("BLUETOOTH") != std::string::npos) {
    return "bluetooth";
  }
  if (upper.find("HDAUDIO") != std::string::npos) return "builtIn";
  return "unknown";
}

void AppendS16(const BYTE* data, UINT32 frames, const WAVEFORMATEX* format,
               std::vector<uint8_t>* out) {
  const int channels = format->nChannels;
  if (channels <= 0 || frames == 0) return;
  const bool extensible = format->wFormatTag == WAVE_FORMAT_EXTENSIBLE;
  WORD bits = format->wBitsPerSample;
  bool is_float = format->wFormatTag == WAVE_FORMAT_IEEE_FLOAT;
  if (extensible && format->cbSize >= 22) {
    const auto* ext = reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(format);
    bits = ext->Samples.wValidBitsPerSample != 0
               ? ext->Samples.wValidBitsPerSample
               : format->wBitsPerSample;
    // De GUID uit ksmedia.h is een extern symbool. Hier staat hij lokaal,
    // zodat de runner geen ksuser.lib nodig heeft.
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
  // An unrecognised mix format is silence of the right length, so the
  // clock stays honest instead of writing a format Dart cannot read.
  memset(dst, 0, static_cast<size_t>(frames) * channels * 2);
}

void PostEnded(const char* cause) {
  if (g_window == nullptr) return;
  auto* text = new std::string(cause);
  PostMessage(g_window, kMicCaptureMessage, kEndedMessage,
              reinterpret_cast<LPARAM>(text));
}

void PostPcm(std::vector<uint8_t> bytes) {
  if (g_window == nullptr || bytes.empty()) return;
  auto* owned = new std::vector<uint8_t>(std::move(bytes));
  PostMessage(g_window, kMicCaptureMessage, kPcmMessage,
              reinterpret_cast<LPARAM>(owned));
}

struct CaptureArgs {
  std::wstring device_id;
  bool use_default = false;
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
    explicit Notify(std::wstring id, bool use_default)
        : id_(std::move(id)), use_default_(use_default) {}
    STDMETHODIMP QueryInterface(REFIID riid, void** object) override {
      if (riid == __uuidof(IUnknown) || riid == __uuidof(IMMNotificationClient)) {
        *object = this;
        return S_OK;
      }
      *object = nullptr;
      return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return 1; }
    STDMETHODIMP_(ULONG) Release() override { return 1; }
    STDMETHODIMP OnDeviceStateChanged(LPCWSTR id, DWORD state) override {
      if (id != nullptr && id_ == id && state != DEVICE_STATE_ACTIVE) {
        PostEnded("sourceLost");
        SetEvent(g_stop);
      }
      return S_OK;
    }
    STDMETHODIMP OnDeviceAdded(LPCWSTR) override { return S_OK; }
    STDMETHODIMP OnDeviceRemoved(LPCWSTR id) override {
      return OnDeviceStateChanged(id, DEVICE_STATE_NOTPRESENT);
    }
    STDMETHODIMP OnDefaultDeviceChanged(EDataFlow flow, ERole,
                                        LPCWSTR) override {
      // A new default while we were on the default is a device switch.
      // Stop. Do not reopen on the new endpoint.
      if (use_default_ && flow == eCapture) {
        PostEnded("sourceLost");
        SetEvent(g_stop);
      }
      return S_OK;
    }
    STDMETHODIMP OnPropertyValueChanged(LPCWSTR, const PROPERTYKEY) override {
      return S_OK;
    }

   private:
    std::wstring id_;
    bool use_default_;
  };

  HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                CLSCTX_ALL, __uuidof(IMMDeviceEnumerator),
                                reinterpret_cast<void**>(&enumerator));
  Notify* notify = nullptr;
  if (SUCCEEDED(hr)) {
    if (args->use_default) {
      hr = enumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &device);
    } else {
      hr = enumerator->GetDevice(args->device_id.c_str(), &device);
    }
  }
  if (SUCCEEDED(hr) && device != nullptr) {
    LPWSTR id = nullptr;
    if (SUCCEEDED(device->GetId(&id)) && id != nullptr) {
      notify = new Notify(id, args->use_default);
      CoTaskMemFree(id);
      enumerator->RegisterEndpointNotificationCallback(notify);
    }
    hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                          reinterpret_cast<void**>(&client));
  }
  if (SUCCEEDED(hr)) {
    hr = client->GetMixFormat(&mix);
  }
  if (SUCCEEDED(hr)) {
    hr = client->Initialize(AUDCLNT_SHAREMODE_SHARED,
                            AUDCLNT_STREAMFLAGS_EVENTCALLBACK, 1000000, 0, mix,
                            nullptr);
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
        static_cast<size_t>(std::max(args->rate, 1)) * args->channels;
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
          std::vector<BYTE> zeros(static_cast<size_t>(frames) * mix->nBlockAlign,
                                  0);
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

EncodableList ListInputs() {
  EncodableList inputs;
  IMMDeviceEnumerator* enumerator = nullptr;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                              __uuidof(IMMDeviceEnumerator),
                              reinterpret_cast<void**>(&enumerator)))) {
    return inputs;
  }
  std::wstring default_id;
  IMMDevice* def = nullptr;
  if (SUCCEEDED(
          enumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &def)) &&
      def != nullptr) {
    LPWSTR id = nullptr;
    if (SUCCEEDED(def->GetId(&id)) && id != nullptr) {
      default_id = id;
      CoTaskMemFree(id);
    }
    def->Release();
  }
  IMMDeviceCollection* devices = nullptr;
  if (FAILED(enumerator->EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE,
                                            &devices))) {
    enumerator->Release();
    return inputs;
  }
  UINT count = 0;
  devices->GetCount(&count);
  for (UINT i = 0; i < count; ++i) {
    IMMDevice* device = nullptr;
    if (FAILED(devices->Item(i, &device)) || device == nullptr) continue;
    LPWSTR id = nullptr;
    device->GetId(&id);
    IPropertyStore* store = nullptr;
    device->OpenPropertyStore(STGM_READ, &store);
    std::string label = "Microphone";
    std::string transport = "unknown";
    if (store != nullptr) {
      const std::string friendly =
          ReadStringProp(store, PKEY_Device_FriendlyName);
      if (!friendly.empty()) label = friendly;
      transport = TransportOf(ReadStringProp(store, PKEY_Device_EnumeratorName));
      store->Release();
    }
    EncodableMap item;
    item[EncodableValue("id")] =
        EncodableValue(id == nullptr ? "" : WideToUtf8(id));
    item[EncodableValue("label")] = EncodableValue(label);
    item[EncodableValue("transport")] = EncodableValue(transport);
    item[EncodableValue("isDefault")] =
        EncodableValue(id != nullptr && default_id == id);
    inputs.push_back(EncodableValue(item));
    if (id != nullptr) CoTaskMemFree(id);
    device->Release();
  }
  devices->Release();
  enumerator->Release();
  return inputs;
}

void Fail(std::unique_ptr<flutter::MethodResult<EncodableValue>> result,
          const std::string& code, const std::string& message) {
  result->Error(code, message);
}

void HandleOpen(const EncodableValue* arguments,
                std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (g_running) {
    Fail(std::move(result), "sourceUnavailable", "microfoon is al open");
    return;
  }
  std::string device_id;
  if (arguments != nullptr && std::holds_alternative<EncodableMap>(*arguments)) {
    const auto& map = std::get<EncodableMap>(*arguments);
    const auto it = map.find(EncodableValue("deviceId"));
    if (it != map.end() && std::holds_alternative<std::string>(it->second)) {
      device_id = std::get<std::string>(it->second);
    }
  }
  if (g_stop == nullptr) g_stop = CreateEvent(nullptr, TRUE, FALSE, nullptr);
  ResetEvent(g_stop);
  auto* args = new CaptureArgs();
  args->device_id = Utf8ToWide(device_id);
  args->use_default = device_id.empty();
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
    Fail(std::move(result), code, "microfoon openen mislukt");
    return;
  }
  g_running = true;
  EncodableMap ok;
  ok[EncodableValue("sampleRate")] = EncodableValue(rate);
  ok[EncodableValue("channels")] = EncodableValue(channels);
  result->Success(EncodableValue(ok));
}

void HandleStop() {
  if (g_stop != nullptr) SetEvent(g_stop);
  if (g_thread.joinable()) g_thread.join();
  g_running = false;
}

class MicEvents : public flutter::StreamHandler<EncodableValue> {
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

std::unique_ptr<flutter::MethodChannel<EncodableValue>> g_methods;
std::unique_ptr<flutter::EventChannel<EncodableValue>> g_channel;

}  // namespace

void RegisterMicCapture(flutter::BinaryMessenger* messenger, HWND window) {
  g_window = window;
  g_methods = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "ocideck/mic_capture",
      &flutter::StandardMethodCodec::GetInstance());
  g_channel = std::make_unique<flutter::EventChannel<EncodableValue>>(
      messenger, "ocideck/mic_capture_pcm",
      &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetStreamHandler(
      std::unique_ptr<flutter::StreamHandler<EncodableValue>>(
          std::make_unique<MicEvents>()));
  g_methods->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() == "describe") {
          EncodableMap body;
          body[EncodableValue("availability")] =
              EncodableValue("tryAfterPermission");
          body[EncodableValue("inputs")] = EncodableValue(ListInputs());
          result->Success(EncodableValue(body));
        } else if (call.method_name() == "open") {
          HandleOpen(call.arguments(), std::move(result));
        } else if (call.method_name() == "stop") {
          HandleStop();
          result->Success();
        } else if (call.method_name() == "freeBytes") {
          std::string path;
          if (call.arguments() != nullptr &&
              std::holds_alternative<EncodableMap>(*call.arguments())) {
            const auto& map = std::get<EncodableMap>(*call.arguments());
            const auto it = map.find(EncodableValue("path"));
            if (it != map.end() &&
                std::holds_alternative<std::string>(it->second)) {
              path = std::get<std::string>(it->second);
            }
          }
          ULARGE_INTEGER free{};
          const std::wstring wide = Utf8ToWide(path);
          if (!wide.empty() &&
              GetDiskFreeSpaceExW(wide.c_str(), &free, nullptr, nullptr)) {
            result->Success(EncodableValue(static_cast<int64_t>(free.QuadPart)));
          } else {
            result->Success(EncodableValue());
          }
        } else {
          result->NotImplemented();
        }
      });
}

void ShutdownMicCapture() {
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

void HandleMicCaptureMessage(WPARAM wparam, LPARAM lparam) {
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
