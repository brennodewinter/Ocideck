import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Bewaakt dát de platformbuilds afgaan — niet wát ze bouwen.
///
/// Geen enkele poort van dit project bouwt een desktop-app: `make check` en de
/// Forgejo-gates draaien `flutter test`. De builds zaten daardoor alleen in de
/// releaseketen, en dat kostte de release van v0.4.9: de nativeapi-migratie
/// (#1741) bracht een plugin mee die een systeembibliotheek eist die niemand
/// installeerde, CMake viel om vóór er iets gecompileerd was, en de eerste
/// machine die dat merkte was de tag. Alle poorten stonden intussen groen.
///
/// Sindsdien bouwt elk platform ná een merge, maar alleen wanneer er iets
/// veranderde dat een native build kan breken. Dat padfilter is precies waar
/// die bescherming stil kan verdwijnen — `.tool-versions` ontbrak er eerst in,
/// waardoor een kále Flutter-bump (die niets aan `pubspec.lock` verandert) de
/// build oversloeg. Een build die niet afgaat bewaakt niets.
void main() {
  /// De invoeren die een native build kunnen breken, met de reden erbij: die
  /// reden is wat een volgende lezer nodig heeft om te beoordelen of hij er een
  /// weg mag halen.
  const gedeeldeInvoer = {
    'pubspec.lock': 'de opgeloste afhankelijkheden — hier kwam #1741 binnen',
    'pubspec.yaml': 'een nieuwe of gewijzigde plugin',
    '.tool-versions':
        'de Flutter-pin: andere compiler, andere engine, andere '
        'gegenereerde build-bestanden',
    'third_party/**': 'de gevendorde pakketten',
  };

  /// Per workflow: het bestand, de eigen platformmap, en of het een
  /// Forgejo- of spiegel-workflow is.
  const workflows = {
    '.forgejo/workflows/linux-build.yml': 'linux/**',
    '.forgejo/workflows/macos-build.yml': 'macos/**',
    '.github/workflows/windows-native-check.yml': 'windows/**',
  };

  for (final entry in workflows.entries) {
    group(entry.key, () {
      final text = File(entry.key).readAsStringSync();

      test('draait na een merge naar main', () {
        expect(
          RegExp(r'push:\s*\n\s*branches:\s*\[main\]').hasMatch(text),
          isTrue,
          reason:
              '${entry.key} bouwt niet meer na een merge; dan is de '
              'releaseketen weer de eerste die het merkt',
        );
      });

      test('blijft ook met de hand te starten', () {
        expect(
          text.contains('workflow_dispatch:'),
          isTrue,
          reason: 'een build op afroep is de enige route zonder tag',
        );
      });

      test('noemt elke invoer die een native build kan breken', () {
        for (final invoer in {
          ...gedeeldeInvoer,
          entry.value: 'de platformeigen runner en zijn build-bestanden',
        }.entries) {
          expect(
            text.contains("'${invoer.key}'"),
            isTrue,
            reason:
                '${entry.key} slaat een merge over die ${invoer.key} raakt '
                '(${invoer.value})',
          );
        }
      });
    });
  }

  group('de generale repetitie bij een toolchain-bump', () {
    final text = File(
      '.forgejo/workflows/toolchain-rehearsal.yml',
    ).readAsStringSync();

    test('gaat af op een PR die de Flutter-pin raakt', () {
      expect(text.contains('pull_request:'), isTrue);
      expect(
        text.contains("'.tool-versions'"),
        isTrue,
        reason:
            'de repetitie hoort te draaien op precies de wijziging die alle '
            'drie de platformen tegelijk raakt',
      );
    });

    test('faalt zichtbaar in plaats van stil over te slaan', () {
      expect(
        text.contains('exit 1'),
        isTrue,
        reason:
            'een repetitie die een mislukte spiegelrun groen laat is geen '
            'repetitie',
      );
    });

    test('slaat zichzelf over zonder token, in plaats van rood te worden', () {
      // Een PR uit een fork krijgt geen secrets. Rood worden voor iets waar de
      // indiener niets aan kan doen is geen poort maar een drempel.
      expect(text.contains(r'if [ -z "${GH_DISPATCH_TOKEN:-}" ]'), isTrue);
    });
  });
}
