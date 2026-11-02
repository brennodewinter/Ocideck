@TestOn('browser')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_scan_memo.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

void main() {
  test('web: vooruit scannen bewaart bevindingen en warmt de memo', () async {
    expect(kIsWeb, isTrue, reason: 'deze regressie vereist een echte browser');
    clearPrivacyScanMemo();
    const scanner = PrivacyScanner();
    final deck = Deck(
      title: 'Demo',
      slides: [
        Slide.create(
          SlideType.bullets,
        ).copyWith(bullets: ['BSN 728398242 van betrokkene']),
        Slide.create(
          SlideType.bullets,
        ).copyWith(bullets: ['Mail naar jan@voorbeeld-klant.example']),
      ],
    );
    final direct = scanner.scan(deck);
    expect(direct.findings, isNotEmpty);

    await warmPrivacyScanMemo(scanner, deck.slides);
    final warmed = memoizedDeckScan(scanner, deck);

    expect(privacyScanMemoMisses, 0);
    expect(
      warmed.findings,
      orderedEquals([
        for (final finding in direct.findings)
          isA<PrivacyFinding>()
              .having((f) => f.ruleId, 'regel', finding.ruleId)
              .having((f) => f.slideIndex, 'dia', finding.slideIndex)
              .having((f) => f.field, 'veld', finding.field)
              .having((f) => f.start, 'begin', finding.start)
              .having((f) => f.end, 'einde', finding.end)
              .having((f) => f.maskedSample, 'voorbeeld', finding.maskedSample),
      ]),
    );
  });
}
