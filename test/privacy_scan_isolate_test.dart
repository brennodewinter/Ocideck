@TestOn('vm')
library;

import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_scan_memo.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

List<Object?> signature(PrivacyFinding finding) => [
  finding.ruleId,
  finding.family,
  finding.confidence,
  finding.slideIndex,
  finding.field,
  finding.fragmentIndex,
  finding.start,
  finding.end,
  finding.maskedSample,
  finding.role,
  finding.personRole,
];

void main() {
  test(
    'real isolate preserves config and captions without sending reader',
    () async {
      // Like Riverpod's reader, this callback holds unsendable state. Ordinary
      // Flutter warming tests take the no-token synchronous route and miss it.
      final port = ReceivePort();
      final reads = <String>[];
      port.listen((message) => reads.add(message as String));
      addTearDown(port.close);
      final scanner = PrivacyScanner(
        ownIdentity: OwnIdentity.fromLines('author@example.org'),
        disabledRules: {'nl.bsn'},
        regions: {'nl'},
        assetTextReader: (path) {
          port.sendPort.send(path);
          return 'WEBVTT\n\nMail klant@customer.example of author@example.org';
        },
      );
      final slides = [
        Slide.create(
          SlideType.video,
        ).copyWith(videoCaptions: 'mem:captions.vtt'),
        Slide.create(
          SlideType.bullets,
        ).copyWith(bullets: ['BSN 728398242, klant@customer.example']),
        Slide.create(
          SlideType.video,
        ).copyWith(videoCaptions: 'mem:captions.vtt'),
      ];
      final expected = [
        for (final slide in slides)
          [for (final f in scanner.scanSlide(slide, 0).findings) signature(f)],
      ];
      expect(expected.first, isNotEmpty);
      final (_, actual) = await scanPrivacySlidesInIsolate(scanner, slides);
      expect([
        for (final batch in actual) [for (final f in batch) signature(f)],
      ], expected);
      await Future<void>.delayed(Duration.zero);
      expect(
        reads,
        hasLength(3),
        reason: 'two direct scans and one deduplicated snapshot',
      );
    },
  );
}
