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
library;

import 'dart:convert';
import 'dart:io';

import 'log.dart';

/// Atomically write [bytes] to [target] via a sibling temp file + rename.
Future<void> writeBytesAtomic(File target, List<int> bytes) async {
  final tmp = File('${target.path}.tmp');
  try {
    await tmp.writeAsBytes(bytes, flush: true);
    try {
      await tmp.rename(target.path);
    } on FileSystemException {
      // Windows: rename onto an existing file fails. Remove the target and
      // retry — the original is only at risk for this brief, content-free gap,
      // and the written .tmp survives a crash here.
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
