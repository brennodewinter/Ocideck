import 'dart:ffi';
import 'dart:io';

/// Checks a session owner without sending a signal or starting a subprocess.
/// A null result leaves the recovery service's heartbeat fallback in charge.
bool? recoveryProcessIsAlive(int owner) {
  if (owner <= 0 || owner > 0x7fffffff) return null;
  if (Platform.isWindows) return _windowsProcessIsAlive(owner);
  if (!Platform.isMacOS && !Platform.isLinux) return null;
  final errno = _errnoLocation();
  // A zero signal checks for existence and permission without delivering it.
  if (_kill(owner, 0) == 0) return true;
  const noSuchProcess = 3; // ESRCH on macOS and Linux.
  return errno.value == noSuchProcess ? false : null;
}

final _libc = DynamicLibrary.process();
final _kill = _libc
    .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
      'kill',
      isLeaf: true,
    );
final _errnoLocation = _libc
    .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
      Platform.isMacOS ? '__error' : '__errno_location',
      isLeaf: true,
    );

bool? _windowsProcessIsAlive(int owner) {
  const synchronize = 0x00100000;
  const invalidParameter = 87;
  // Resolve and warm the FFI error reader before an API can set its error.
  // First-use initialization would otherwise overwrite that Windows error.
  _getLastError();
  final handle = _openProcess(synchronize, 0, owner);
  if (handle == nullptr) {
    return _getLastError() == invalidParameter ? false : null;
  }
  try {
    return switch (_waitForSingleObject(handle, 0)) {
      0 => false, // WAIT_OBJECT_0: the process has terminated.
      0x102 => true, // WAIT_TIMEOUT: the process is still running.
      _ => null,
    };
  } finally {
    _closeHandle(handle);
  }
}

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _openProcess = _kernel32
    .lookupFunction<
      Pointer<Void> Function(Uint32, Int32, Uint32),
      Pointer<Void> Function(int, int, int)
    >('OpenProcess', isLeaf: true);
final _getLastError = _kernel32
    .lookupFunction<Uint32 Function(), int Function()>(
      'GetLastError',
      isLeaf: true,
    );
final _waitForSingleObject = _kernel32
    .lookupFunction<
      Uint32 Function(Pointer<Void>, Uint32),
      int Function(Pointer<Void>, int)
    >('WaitForSingleObject', isLeaf: true);
final _closeHandle = _kernel32
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'CloseHandle',
      isLeaf: true,
    );
