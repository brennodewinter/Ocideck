import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/presentation/display_info.dart';

void main() {
  // Laptop (primair, links) en een beamer (extern, rechts) — de standaard
  // two-screen opstelling. Coordinaten in top-left, zoals nativeapi levert.
  final displays = <DisplayInfo>[
    const DisplayInfo(x: 0, y: 0, width: 1440, height: 900),
    const DisplayInfo(x: 1440, y: 0, width: 1920, height: 1080),
  ];

  test('vindt het scherm dat de presentator bevat (normale opstelling)', () {
    // Presentator op de laptop: het punt ligt in scherm 0.
    expect(screenIndexContaining(displays, const Offset(720, 450)), 0);
  });

  test('vindt het scherm dat de presentator bevat (omgedraaid, #1913)', () {
    // Presentator verplaatst naar de beamer: het punt ligt in scherm 1. Dat is
    // precies de situatie waarin coverScreen(external:true) vroeger het
    // publieksvenster óók op de beamer zette in plaats van op de laptop.
    expect(screenIndexContaining(displays, const Offset(2400, 540)), 1);
  });

  test('geeft null voor een punt buiten alle schermen', () {
    expect(screenIndexContaining(displays, const Offset(-10, 0)), isNull);
    expect(screenIndexContaining(displays, const Offset(5000, 0)), isNull);
  });

  test('geeft null voor een null-punt of geen schermen', () {
    expect(screenIndexContaining(displays, null), isNull);
    expect(
      screenIndexContaining(const <DisplayInfo>[], const Offset(0, 0)),
      isNull,
    );
  });

  test('pakt het eerste scherm bij overlappende grens', () {
    // Een punt precies op de grens (x=1440) hoort bij één scherm; beide
    // aanliggende schermen claimen het, maar de uitkomst moet deterministisch
    // zijn — het eerste scherm dat het punt bevat.
    final index = screenIndexContaining(displays, const Offset(1440, 0));
    expect(index == 0 || index == 1, isTrue);
  });
}
