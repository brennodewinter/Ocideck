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

import 'package:flutter/foundation.dart';

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
  var targetRemoved = false;
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
        targetRemoved = true;
        await tmp.rename(target.path);
      } else {
        rethrow;
      }
    }
  } catch (e) {
    // Log the write failure (we still rethrow) and never leave a stray temp —
    // unless the target is already gone and the retry failed too, in which case
    // this temp is the only copy of the content that is left. Same reasoning as
    // in [writeBytesAtomicSync].
    logWarning('writeBytesAtomic: write failed', e);
    if (!targetRemoved && await tmp.exists()) {
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

/// [writeBytesAtomicSync] with a bounded retry, for a target another process
/// may be holding open for a moment.
///
/// On Windows a file that was just read stays locked briefly — a virus scanner
/// on a build machine is the classic holder — and then both halves of the
/// atomic write fail: `rename` refuses to replace an existing file, and the
/// delete-then-rename fallback cannot delete what someone else has open
/// (errno 32). The image crop dialog lost every rotation to this, silently.
///
/// Blocking rather than async on purpose: the one caller must be able to close
/// its dialog immediately, and an `await` here would make the window wait for
/// disk IO. Blocking does not prevent the release either — the holder is a
/// different process. Same shape as `deleteTempDir` in test/support, which
/// exists for the same errno.
///
/// Throws the last error when every attempt failed, so the caller can report
/// *why* instead of falling silent. [pause] is a test seam so a test does not
/// have to spend the real delay.
void writeBytesAtomicSyncRetrying(
  File target,
  List<int> bytes, {
  int attempts = 5,
  Duration retryDelay = const Duration(milliseconds: 40),
  @visibleForTesting void Function(File tmp, String destination)? renameOnce,
  @visibleForTesting void Function(Duration delay)? pause,
}) {
  // Elke poging die het doel verwijderde en daarna alsnog struikelde, laat zijn
  // tijdelijke bestand staan: dat is dan de enige kopie van de inhoud.
  final recoveries = <File>[];
  for (var attempt = 1; ; attempt++) {
    try {
      writeBytesAtomicSync(
        target,
        bytes,
        renameOnce: renameOnce,
        onRecoveryKept: recoveries.add,
      );
      // Geslaagd: een herstelkopie van een eerdere poging is nu overbodig, en
      // laten staan zou een `foto.png.3.tmp` naast het beeld van de gebruiker
      // achterlaten.
      for (final recovery in recoveries) {
        try {
          if (recovery.existsSync()) recovery.deleteSync();
        } on Object catch (e) {
          logWarning('writeBytesAtomicSyncRetrying: recovery cleanup', e);
        }
      }
      return;
    } on Object {
      if (attempt >= attempts) rethrow;
      (pause ?? sleep)(retryDelay);
    }
  }
}

/// Sync variant of [writeBytesAtomic] for callers that can't await (e.g. a
/// dialog `onPressed` that must pop before the test framework pumps). Same
/// temp-file + rename strategy, *including* the Windows delete-then-rename
/// fallback; throws on failure.
///
/// The fallback used to be missing here while the library doc above already
/// promised it, and the effect was silent: on Windows every sync atomic write
/// onto an *existing* file threw, and the one caller — rotating an image in the
/// crop dialog — swallows write errors so the crop choice survives a failed
/// write. Rotating therefore did nothing at all on Windows, without a single
/// message; the mirror's Windows job was red on exactly that test.
///
/// [renameOnce] exists only so a test can prove the fallback without a real
/// Windows rename failure (same idiom as `deleteOnce` in
/// `test/support/temp_dir.dart`); leave it out in production use.
///
/// [onRecoveryKept] is handed the temp file in the one case where it is
/// deliberately left behind: the target was already deleted and the retry
/// failed, so this temp holds the only copy of the content. A caller that
/// retries (see [writeBytesAtomicSyncRetrying]) removes it once a later
/// attempt succeeds; a caller that does not gets a recovery file rather than
/// silence.
void writeBytesAtomicSync(
  File target,
  List<int> bytes, {
  @visibleForTesting void Function(File tmp, String destination)? renameOnce,
  void Function(File recovery)? onRecoveryKept,
}) {
  final rename = renameOnce ?? (File tmp, String dest) => tmp.renameSync(dest);
  final tmp = File('${target.path}.${_tempCounter++}.tmp');
  // Zodra dit waar is, is `tmp` de enige kopie die er nog van de inhoud is.
  var targetRemoved = false;
  try {
    tmp.writeAsBytesSync(bytes, flush: true);
    try {
      rename(tmp, target.path);
    } on FileSystemException {
      // Windows: rename onto an existing file fails. Identical reasoning and
      // identical ceiling as in [writeBytesAtomic] — the target is only absent
      // for a content-free gap, and the complete `.tmp` survives it.
      if (target.existsSync()) {
        target.deleteSync();
        targetRemoved = true;
        rename(tmp, target.path);
      } else {
        rethrow;
      }
    }
  } catch (e) {
    logWarning('writeBytesAtomicSync: write failed', e);
    // Ruim het tijdelijke bestand op — behálve wanneer het doel al verwijderd
    // is en de tweede rename alsnog faalde. Dan is dit geen rommel maar de
    // enige overgebleven kopie, en weggooien maakt van een mislukte
    // schrijfbeurt een verloren bestand. Precies dat gat zat hier: de
    // Windows-terugval verwijdert het doel, en de opruiming eronder gooide
    // daarna ook nog het herstelbestand weg.
    if (targetRemoved) {
      onRecoveryKept?.call(tmp);
    } else if (tmp.existsSync()) {
      try {
        tmp.deleteSync();
      } catch (e) {
        logWarning('writeBytesAtomicSync: temp cleanup failed', e);
      }
    }
    rethrow;
  }
}
