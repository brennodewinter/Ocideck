// Copyright Stichting LibreKAT. EUPL-1.2.
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <wrl/client.h>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cwchar>

using Microsoft::WRL::ComPtr;
namespace {
void Le32(FILE* file, uint32_t n) {
  const unsigned char bytes[] = {static_cast<unsigned char>(n),
      static_cast<unsigned char>(n >> 8), static_cast<unsigned char>(n >> 16),
      static_cast<unsigned char>(n >> 24)};
  std::fwrite(bytes, 1, 4, file);
}
void Header(FILE* file, uint32_t bytes) {
  std::fseek(file, 0, SEEK_SET);
  std::fwrite("RIFF", 1, 4, file); Le32(file, 36 + bytes);
  std::fwrite("WAVEfmt ", 1, 8, file); Le32(file, 16);
  const unsigned char format[] = {1, 0, 1, 0};
  std::fwrite(format, 1, 4, file); Le32(file, 16000); Le32(file, 32000);
  const unsigned char size[] = {2, 0, 16, 0};
  std::fwrite(size, 1, 4, file);
  std::fwrite("data", 1, 4, file); Le32(file, bytes);
}
HRESULT Decode(const wchar_t* input, FILE* output) {
  ComPtr<IMFSourceReader> reader;
  HRESULT hr = MFCreateSourceReaderFromURL(input, nullptr, &reader);
  if (FAILED(hr)) return hr;
  hr = reader->SetStreamSelection(MF_SOURCE_READER_ALL_STREAMS, FALSE);
  if (SUCCEEDED(hr)) hr = reader->SetStreamSelection(MF_SOURCE_READER_FIRST_AUDIO_STREAM, TRUE);
  ComPtr<IMFMediaType> type;
  if (SUCCEEDED(hr)) hr = MFCreateMediaType(&type);
  if (SUCCEEDED(hr)) hr = type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
  if (SUCCEEDED(hr)) hr = type->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
  if (SUCCEEDED(hr)) hr = type->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 1);
  if (SUCCEEDED(hr)) hr = type->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, 16000);
  if (SUCCEEDED(hr)) hr = type->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
  if (SUCCEEDED(hr)) hr = type->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, 2);
  if (SUCCEEDED(hr)) hr = type->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 32000);
  if (SUCCEEDED(hr)) hr = reader->SetCurrentMediaType(MF_SOURCE_READER_FIRST_AUDIO_STREAM, nullptr, type.Get());
  if (FAILED(hr)) return hr;
  uint32_t written = 0;
  Header(output, 0);
  while (true) {
    ComPtr<IMFSample> sample;
    DWORD flags = 0;
    hr = reader->ReadSample(MF_SOURCE_READER_FIRST_AUDIO_STREAM, 0, nullptr,
                            &flags, nullptr, &sample);
    if (FAILED(hr) || (flags & MF_SOURCE_READERF_ERROR)) return E_FAIL;
    if (sample) {
      ComPtr<IMFMediaBuffer> buffer;
      hr = sample->ConvertToContiguousBuffer(&buffer);
      if (FAILED(hr)) return hr;
      BYTE* data = nullptr; DWORD length = 0;
      hr = buffer->Lock(&data, nullptr, &length);
      if (FAILED(hr)) return hr;
      // Bound the decoded staging file to the same 2 GiB input budget.
      const bool valid = length % 2 == 0 && length <= 0x7fffffffU - written;
      const bool saved = valid && std::fwrite(data, 1, length, output) == length;
      buffer->Unlock();
      if (!saved) return E_FAIL;
      written += length;
    }
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
  }
  if (written == 0) return E_FAIL;
  Header(output, written);
  return std::ferror(output) ? E_FAIL : S_OK;
}
}  // namespace
int wmain(int argc, wchar_t** argv) {
  if (argc != 4 || std::wcscmp(argv[1], L"--decode") != 0) return 2;
  // Only local paths are accepted; no URL source resolver/network fallback.
  if (std::wcsstr(argv[2], L"://") || std::wcsstr(argv[2], L"\\\\")) return 2;
  const HRESULT initialized = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(initialized)) return 1;
  const HRESULT started = MFStartup(MF_VERSION, MFSTARTUP_NOSOCKET);
  HRESULT hr = started;
  FILE* output = nullptr;
  if (SUCCEEDED(hr)) {
    _wfopen_s(&output, argv[3], L"wb");
    hr = output ? Decode(argv[2], output) : E_FAIL;
  }
  if (output && std::fclose(output) != 0) hr = E_FAIL;
  if (FAILED(hr)) _wremove(argv[3]);
  if (SUCCEEDED(started)) MFShutdown();
  CoUninitialize();
  return SUCCEEDED(hr) ? 0 : (hr == MF_E_INVALIDSTREAMNUMBER ? 3 : 1);
}
