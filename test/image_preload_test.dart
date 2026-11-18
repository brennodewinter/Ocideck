import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/image_preload.dart';

class _TrackedCompleter extends OneFrameImageStreamCompleter {
  _TrackedCompleter(super.image);

  final listeners = <ImageStreamListener>{};

  @override
  void addListener(ImageStreamListener listener) {
    listeners.add(listener);
    super.addListener(listener);
  }

  @override
  void removeListener(ImageStreamListener listener) {
    listeners.remove(listener);
    super.removeListener(listener);
  }
}

class _PendingProvider extends ImageProvider<_PendingProvider> {
  final result = Completer<ImageInfo>();
  late final completer = _TrackedCompleter(result.future);

  @override
  Future<_PendingProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _PendingProvider key,
    ImageDecoderCallback decode,
  ) => completer;
}

void main() {
  testWidgets(
    'een vastgelopen lading verloopt en ruimt zijn eigen listener op',
    (tester) async {
      final provider = _PendingProvider();
      const timeout = Duration(milliseconds: 30);
      final preload = preloadExportImage(
        provider,
        ImageConfiguration.empty,
        source: 'images/cloud.png',
        timeout: timeout,
      );
      expect(provider.completer.listeners, hasLength(2)); // cache en voorlader
      final assertion = expectLater(
        preload,
        throwsA(
          isA<ImagePreloadTimeout>()
              .having((e) => e.source, 'source', 'images/cloud.png')
              .having((e) => e.waited, 'waited', timeout),
        ),
      );
      await tester.pump(timeout);
      await assertion;
      expect(provider.completer.listeners, hasLength(1));
      PaintingBinding.instance.imageCache.clear();
      expect(provider.completer.listeners, isEmpty);
      // Een late OS-fout mag na het opruimen geen tweede foutscherm veroorzaken.
      provider.result.completeError(StateError('late I/O error'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('een gewone leesfout behoudt het bestaande placeholdergedrag', (
    tester,
  ) async {
    final provider = _PendingProvider();
    final preload = preloadExportImage(
      provider,
      ImageConfiguration.empty,
      source: 'missing.png',
    );
    provider.result.completeError(StateError('missing'));
    await tester.pump();
    await preload;
    PaintingBinding.instance.imageCache.clear();
    expect(provider.completer.listeners, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
