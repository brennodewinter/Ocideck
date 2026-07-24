import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/iwa_archive.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/iwa_document.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/media_reconstructor.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/proto_wire.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/snappy.dart';
import 'package:ocideck/services/import/importers/keynote/key_context.dart';
import 'package:ocideck/services/import/models/source_video.dart';

import 'helpers/key_fixtures.dart' as fx;

void main() {
  final wire = ProtoWire();
  final archive = IwaArchive(wire);
  final snappy = SnappyDecompressor();

  IwaDocument buildDoc(List<int> recordBytes) {
    final stream = fx.iwaStream(recordBytes);
    final objects = archive.parse(snappy.decompressIwaStream(stream));
    return IwaDocument(objects);
  }

  test('extracts an embedded video', () {
    final packageMetadata = fx.record(
      2,
      100,
      fx.packageMetadataPayload(
        dataInfos: [
          fx.dataInfoPayload(identifier: 100, preferredFileName: 'clip.mp4'),
        ],
      ),
    );
    final movie = fx.record(11, 200, fx.moviePayload(movieDataId: 100));
    final doc = buildDoc([packageMetadata, movie].expand((e) => e).toList());
    final reconstructor = MediaReconstructor(doc);
    final result = reconstructor.extract(doc[11]!, 0);

    expect(result.video, isNotNull);
    expect(result.video!.kind, SourceVideoKind.local);
    expect(result.video!.ref, 'media/clip.mp4');
    expect(result.audioFileName, isNull);
  });

  test('extracts a YouTube video from a remote URL', () {
    final movie = fx.record(
      11,
      200,
      fx.moviePayload(movieRemoteURL: 'https://www.youtube.com/watch?v=abc123'),
    );
    final doc = buildDoc([...movie]);
    final reconstructor = MediaReconstructor(doc);
    final result = reconstructor.extract(doc[11]!, 0);

    expect(result.video, isNotNull);
    expect(result.video!.kind, SourceVideoKind.youtube);
    expect(result.video!.ref, 'https://www.youtube.com/watch?v=abc123');
  });

  test('extracts audio as an audioFileName', () {
    final packageMetadata = fx.record(
      2,
      100,
      fx.packageMetadataPayload(
        dataInfos: [
          fx.dataInfoPayload(identifier: 101, preferredFileName: 'voice.mp3'),
        ],
      ),
    );
    final movie = fx.record(
      11,
      200,
      fx.moviePayload(movieDataId: 101, audioOnly: true),
    );
    final doc = buildDoc([packageMetadata, movie].expand((e) => e).toList());
    final reconstructor = MediaReconstructor(doc);
    final result = reconstructor.extract(doc[11]!, 0);

    expect(result.video, isNull);
    expect(result.audioFileName, 'voice.mp3');
  });

  test('classifies Vimeo URLs', () {
    final movie = fx.record(
      11,
      200,
      fx.moviePayload(movieRemoteURL: 'https://vimeo.com/12345'),
    );
    final doc = buildDoc([...movie]);
    final reconstructor = MediaReconstructor(doc);
    final result = reconstructor.extract(doc[11]!, 0);

    expect(result.video?.kind, SourceVideoKind.vimeo);
    expect(result.video?.ref, 'https://vimeo.com/12345');
  });

  test('classifies generic URLs without a host match', () {
    final movie = fx.record(
      11,
      200,
      fx.moviePayload(movieRemoteURL: 'https://example.com/video.mp4'),
    );
    final doc = buildDoc([...movie]);
    final reconstructor = MediaReconstructor(doc);
    final result = reconstructor.extract(doc[11]!, 0);

    expect(result.video?.kind, SourceVideoKind.url);
    expect(result.video?.ref, 'https://example.com/video.mp4');
  });

  test('falls back to text-based URL classification when URI has no host', () {
    final movie = fx.record(
      11,
      200,
      fx.moviePayload(movieRemoteURL: 'youtube://'),
    );
    final doc = buildDoc([...movie]);
    final reconstructor = MediaReconstructor(doc);
    final result = reconstructor.extract(doc[11]!, 0);

    expect(result.video?.kind, SourceVideoKind.youtube);
    expect(result.video?.ref, 'youtube://');
  });

  test('returns null when there is no media reference', () {
    final movie = fx.record(11, 200, fx.moviePayload());
    final doc = buildDoc([...movie]);
    final reconstructor = MediaReconstructor(doc);
    final result = reconstructor.extract(doc[11]!, 0);

    expect(result.video, isNull);
    expect(result.audioFileName, isNull);
  });

  test(
    'loads a poster image and sanitizes a path with directory separators',
    () {
      final packageMetadata = fx.record(
        2,
        100,
        fx.packageMetadataPayload(
          dataInfos: [
            fx.dataInfoPayload(
              identifier: 100,
              preferredFileName: 'dir/clip.mp4',
            ),
            fx.dataInfoPayload(
              identifier: 101,
              preferredFileName: 'poster.jpg',
            ),
          ],
        ),
      );
      final movie = fx.record(
        11,
        200,
        fx.moviePayload(movieDataId: 100, posterImageDataId: 101),
      );
      final doc = buildDoc([packageMetadata, movie].expand((e) => e).toList());

      final archive = Archive()
        ..addFile(ArchiveFile('Data/poster.jpg', 4, [0xFF, 0xD8, 0xFF, 0xE0]));
      final reconstructor = MediaReconstructor(doc, ctx: KeyContext(archive));
      final result = reconstructor.extract(doc[11]!, 0);

      expect(result.video, isNotNull);
      expect(result.video!.ref, 'media/clip.mp4');
      expect(result.video!.thumbnail, isNotNull);
      expect(result.video!.thumbnail!.ext, 'jpg');
    },
  );

  test('audio file name is sanitized with p.basename', () {
    final packageMetadata = fx.record(
      2,
      100,
      fx.packageMetadataPayload(
        dataInfos: [
          fx.dataInfoPayload(
            identifier: 101,
            preferredFileName: 'Data/audio.mp3',
          ),
        ],
      ),
    );
    final movie = fx.record(
      11,
      200,
      fx.moviePayload(movieDataId: 101, audioOnly: true),
    );
    final doc = buildDoc([packageMetadata, movie].expand((e) => e).toList());
    final reconstructor = MediaReconstructor(doc);
    final result = reconstructor.extract(doc[11]!, 0);

    expect(result.audioFileName, 'audio.mp3');
  });
}
