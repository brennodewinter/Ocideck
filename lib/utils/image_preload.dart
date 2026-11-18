import 'dart:async';

import 'package:flutter/painting.dart';

import 'log.dart';

const imagePreloadTimeout = Duration(seconds: 20);

/// Een lees- of decodeeractie leverde niet op tijd een afbeelding op.
class ImagePreloadTimeout implements Exception {
  const ImagePreloadTimeout(this.source, this.waited);

  final String source;
  final Duration waited;

  @override
  String toString() =>
      'ImagePreloadTimeout: $source (${waited.inMilliseconds} ms)';
}

/// Laadt één exportafbeelding met een deadline en ruimt de eigen listener op.
///
/// Alleen precacheImage(...).timeout(...) begrenst de aanroeper: de verborgen
/// precache-listener blijft dan aan een vastgelopen decode hangen. Hier gaat
/// die ook bij een time-out weg. De rasterizer beheert en wist de image-cache.
/// Gewone lees-/decodefouten houden hun bestaande placeholdergedrag.
Future<void> preloadExportImage(
  ImageProvider provider,
  ImageConfiguration configuration, {
  required String source,
  Duration timeout = imagePreloadTimeout,
}) async {
  final ready = Completer<void>();
  final stream = provider.resolve(configuration);
  final listener = ImageStreamListener(
    (image, _) {
      image.dispose();
      if (!ready.isCompleted) ready.complete();
    },
    onError: (Object error, StackTrace? stack) {
      if (!ready.isCompleted) ready.complete();
    },
  );
  try {
    stream.addListener(listener);
    await ready.future.timeout(
      timeout,
      onTimeout: () {
        // Een OS-lezing kan later alsnog falen. Deze foutlistener houdt geen
        // beeld of actieve stream vast, maar voorkomt een ongehanteerde fout
        // nadat de gewone listener en de exportcache al zijn opgeruimd.
        stream.completer?.addEphemeralErrorListener((error, stack) {
          logWarning('Exportafbeelding: late laadfout na time-out', error);
        });
        throw ImagePreloadTimeout(source, timeout);
      },
    );
  } finally {
    stream.removeListener(listener);
  }
}
