/// Atomic file writes.
///
/// A plain `File.writeAsString`/`writeAsBytes` truncates the target *first* and
/// then streams the new content in. A crash, full disk or process kill midway
/// leaves a half-written, corrupt file — and for a presentation editor that
/// means the user's original deck is gone. These helpers write to a sibling
/// `<path>.tmp` and then rename it onto the target, so the original stays intact
/// until the complete new content is durably on disk.
///
/// `rename` is atomic on POSIX (it overwrites the destination in one syscall).
/// On Windows `rename` fails if the destination exists, so we fall back to
/// delete-then-rename; the only non-atomic gap there contains no content write
/// and a crash inside it leaves the fully-written `.tmp` behind as a recovery
/// source.
///
/// ponytail: `flush: true` calls `fsync()` on POSIX and `FlushFileBuffers`
/// on Windows — on Linux that suffices. On macOS, however, `fsync()` only
/// flushes to the disk cache, not to the platter; `fcntl(fd, F_FULLFSYNC, 0)`
/// is needed for that. Additionally, there is no `fsync` of the parent
/// directory after the `rename`, so the rename metadata may not be persistent
/// after power loss. Both require a `dart:ffi` call to the native syscall
/// (Dart's `dart:io` exposes no file descriptor or `fcntl`). Ceiling: after
/// power loss on macOS, a "saved" deck may not actually be on disk. Upgrade
/// path: a `dart:ffi` helper that calls `F_FULLFSYNC` on macOS and
/// `fsync(dir_fd)` on the parent directory after rename.
library;

import 'dart:convert';
import 'dart:io';

import 'log.dart';

/// Teller die elke schrijfbeurt binnen dit proces een eigen tijdelijk bestand
/// geeft. Zie [writeBytesAtomic].
int _tempCounter = 0;

/// Atomically write [bytes] to [target] via a sibling temp file + rename.
///
/// De tijdelijke naam is per schrijfbeurt uniek. Met een vaste `<doel>.tmp`
/// deelden twee gelijktijdige schrijvers naar hetzelfde doel één bestand: hun
/// bytes liepen door elkaar, de eerste `rename` verplaatste die mengeling naar
/// het doel, en de tweede faalde met ENOENT — een "opslaan mislukt" op een
/// opslag waar niets mis mee was. Dat kon al met twee decks in dezelfde
/// projectmap, die allebei hun thema-CSS wegschrijven.
Future<void> writeBytesAtomic(File target, List<int> bytes) async {
  final tmp = File('${target.path}.${_tempCounter++}.tmp');
  try {
    await tmp.writeAsBytes(bytes, flush: true);
    try {
      await tmp.rename(target.path);
    } on FileSystemException {
      // ponytail: Windows: rename onto an existing file fails. Remove the
      // target and retry — the original is only at risk for this brief,
      // content-free gap, and the written .tmp survives a crash here. A truly
      // atomic replace on Windows requires `MoveFileEx` with
      // `MOVEFILE_REPLACE_EXISTING` via `dart:ffi`; Dart's `rename` uses
      // `MoveFile` without that flag. Ceiling: on a crash between `delete`
      // and `rename` the target is briefly absent from disk (the `.tmp`
      // survives as recovery). Upgrade path: `dart:ffi` call to
      // `MoveFileExW`.
      if (await target.exists()) {
        await target.delete();
        await tmp.rename(target.path);
      } else {
        rethrow;
      }
    }
  } catch (e) {
    // Log the write failure (we still rethrow) and never leave a stray temp.
    logWarning('writeBytesAtomic: write failed', e);
    if (await tmp.exists()) {
      try {
        await tmp.delete();
      } catch (e) {
        // Best effort; surfacing the original write error matters more.
        logWarning('writeBytesAtomic: temp cleanup failed', e);
      }
    }
    rethrow;
  }
}

/// Atomically write [contents] (UTF-8) to [target].
Future<void> writeStringAtomic(File target, String contents) {
  return writeBytesAtomic(target, utf8.encode(contents));
}

/// Sync variant of [writeBytesAtomic] for callers that can't await (e.g. a
/// dialog `onPressed` that must pop before the test framework pumps). Same
/// temp-file + rename strategy; throws on failure.
void writeBytesAtomicSync(File target, List<int> bytes) {
  final tmp = File('${target.path}.${_tempCounter++}.tmp');
  try {
    tmp.writeAsBytesSync(bytes, flush: true);
    tmp.renameSync(target.path);
  } catch (e) {
    logWarning('writeBytesAtomicSync: write failed', e);
    if (tmp.existsSync()) {
      try {
        tmp.deleteSync();
      } catch (e) {
        logWarning('writeBytesAtomicSync: temp cleanup failed', e);
      }
    }
    rethrow;
  }
}
