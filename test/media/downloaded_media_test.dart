import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/media/downloaded_media.dart';
import 'package:ocideck/services/media/downloaded_media_stub.dart' as stub;
import 'package:ocideck/services/media/downloaded_media_web.dart' as browser;
import 'package:ocideck/services/transcription/transcription_errors.dart';
import 'package:ocideck/services/web_asset_store.dart';

void main() {
  test(
    'concurrent release shares work and failed cleanup can be retried',
    () async {
      var calls = 0;
      final pending = Completer<void>();
      final media = DownloadedMedia('owned', () {
        calls++;
        return pending.future;
      });
      final first = media.release();
      final second = media.release();
      expect(identical(first, second), isTrue);
      pending.complete();
      await first;
      await media.release();
      expect(calls, 1);
      var failures = 0;
      final retry = DownloadedMedia('retry', () async {
        if (++failures == 1) {
          throw const FileSystemException('controlled cleanup failure');
        }
      });
      await expectLater(retry.release(), throwsA(isA<FileSystemException>()));
      await retry.release();
      expect(failures, 2);
    },
  );

  test(
    'native source bytes are preserved privately and removed on release',
    () async {
      final bytes = Uint8List.fromList([0, 255, 128]);
      final media = await stageDownloadedMedia(bytes, 'wav');
      final file = File(media.path);
      expect(await file.readAsBytes(), bytes);
      final directory = file.parent;
      await media.release();
      await media.release();
      expect(await directory.exists(), isFalse);
    },
  );

  test(
    'browser staging is leased, budgeted and collected after release',
    () async {
      WebAssetStore.clear();
      addTearDown(WebAssetStore.clear);
      addTearDown(WebAssetStore.registerRoots(() => {}));
      final media = await browser.stageDownloadedMedia(
        Uint8List.fromList([0, 255]),
        'wav',
      );
      WebAssetStore.collectGarbage();
      expect(WebAssetStore.bytesFor(media.path), [0, 255]);
      await media.release();
      expect(WebAssetStore.totalBytes, 0);
    },
  );

  test(
    'invalid source type and unavailable platform do not produce staging',
    () async {
      expect(
        () => stageDownloadedMedia(Uint8List(1), '../unsafe'),
        throwsA(isA<CapacityExceeded>()),
      );
      await expectLater(
        stub.stageDownloadedMedia(Uint8List(1), 'wav'),
        throwsA(isA<UnsupportedSource>()),
      );
    },
  );
}
