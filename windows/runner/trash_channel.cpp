#include "trash_channel.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shobjidl.h>
#include <shellapi.h>
#include <wrl.h>

#include <memory>
#include <string>

namespace {
using Microsoft::WRL::ComPtr;
using flutter::EncodableValue;
using flutter::EncodableMap;

// The Shell may downgrade a delete to permanent deletion. Veto that operation
// in PreDeleteItem, including a retry after a failed recycle attempt.
class RecycleOnly final : public Microsoft::WRL::RuntimeClass<
    Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>,
    IFileOperationProgressSink> {
 public:
  bool recycled = false;
  HRESULT STDMETHODCALLTYPE PreDeleteItem(DWORD flags, IShellItem*) override {
    return (flags & TSF_DELETE_RECYCLE_IF_POSSIBLE) ? S_OK : E_ABORT;
  }
  HRESULT STDMETHODCALLTYPE PostDeleteItem(DWORD, IShellItem*, HRESULT hr,
                                           IShellItem* destination) override {
    recycled = SUCCEEDED(hr) && destination != nullptr;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE StartOperations() override { return S_OK; }
  HRESULT STDMETHODCALLTYPE FinishOperations(HRESULT) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE UpdateProgress(UINT, UINT) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE ResetTimer() override { return S_OK; }
  HRESULT STDMETHODCALLTYPE PauseTimer() override { return S_OK; }
  HRESULT STDMETHODCALLTYPE ResumeTimer() override { return S_OK; }
  HRESULT STDMETHODCALLTYPE PreRenameItem(DWORD, IShellItem*, LPCWSTR) override { return E_ABORT; }
  HRESULT STDMETHODCALLTYPE PostRenameItem(DWORD, IShellItem*, LPCWSTR, HRESULT, IShellItem*) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE PreMoveItem(DWORD, IShellItem*, IShellItem*, LPCWSTR) override { return E_ABORT; }
  HRESULT STDMETHODCALLTYPE PostMoveItem(DWORD, IShellItem*, IShellItem*, LPCWSTR, HRESULT, IShellItem*) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE PreCopyItem(DWORD, IShellItem*, IShellItem*, LPCWSTR) override { return E_ABORT; }
  HRESULT STDMETHODCALLTYPE PostCopyItem(DWORD, IShellItem*, IShellItem*, LPCWSTR, HRESULT, IShellItem*) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE PreNewItem(DWORD, IShellItem*, LPCWSTR) override { return E_ABORT; }
  HRESULT STDMETHODCALLTYPE PostNewItem(DWORD, IShellItem*, LPCWSTR, LPCWSTR, DWORD, HRESULT, IShellItem*) override { return S_OK; }
};

bool Recycle(const std::string& path, HWND owner) {
  if (path.empty() || path.find('\0') != std::string::npos) return false;
  const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                        path.data(), static_cast<int>(path.size()), nullptr, 0);
  if (count <= 0) return false;
  std::wstring wide(count, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path.data(),
                      static_cast<int>(path.size()), wide.data(), count);
  // Network shares do not have a local system recycle bin.
  if (wide.rfind(L"\\\\", 0) == 0 || wide.size() < 3 || wide[1] != L':') return false;
  ComPtr<IShellItem> item;
  if (FAILED(SHCreateItemFromParsingName(wide.c_str(), nullptr, IID_PPV_ARGS(&item)))) return false;
  ComPtr<IFileOperation> operation;
  if (FAILED(CoCreateInstance(CLSID_FileOperation, nullptr, CLSCTX_INPROC_SERVER,
                               IID_PPV_ARGS(&operation)))) return false;
  auto sink = Microsoft::WRL::Make<RecycleOnly>();
  HRESULT hr = operation->SetOperationFlags(FOF_ALLOWUNDO | FOFX_RECYCLEONDELETE |
      FOFX_EARLYFAILURE | FOF_NOERRORUI | FOF_SILENT | FOF_NOCONFIRMATION);
  if (SUCCEEDED(hr)) hr = operation->SetOwnerWindow(owner);
  if (SUCCEEDED(hr)) hr = operation->DeleteItem(item.Get(), sink.Get());
  if (SUCCEEDED(hr)) hr = operation->PerformOperations();
  BOOL aborted = TRUE;
  if (SUCCEEDED(hr)) hr = operation->GetAnyOperationsAborted(&aborted);
  return SUCCEEDED(hr) && !aborted && sink->recycled;
}
}  // namespace

void RegisterTrashChannel(flutter::BinaryMessenger* messenger, HWND owner) {
  // The messenger owns the handler; the channel wrapper need not outlive it.
  flutter::MethodChannel<EncodableValue> channel(
      messenger, "ocideck/trash", &flutter::StandardMethodCodec::GetInstance());
  channel.SetMethodCallHandler([owner](const auto& call, auto result) {
    if (call.method_name() != "recycle") { result->NotImplemented(); return; }
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    if (args == nullptr) { result->Error("invalid_arguments"); return; }
    const auto it = args->find(EncodableValue("path"));
    const auto* path = it == args->end() ? nullptr : std::get_if<std::string>(&it->second);
    if (path == nullptr) { result->Error("invalid_path"); return; }
    result->Success(EncodableValue(Recycle(*path, owner)));
  });
}
