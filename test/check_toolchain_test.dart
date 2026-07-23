import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_toolchain.dart';

/// De toolchainpoort (#598) bestaat omdat het verschil tussen "wat draait" en
/// "wat er opgeschreven staat" twee keer onopgemerkt is ontstaan. Deze test
/// bewaakt de vergelijking zelf; de aanroep van `flutter` is de dunne schil
/// eromheen.
///
/// Aan het eind staan twee toetsen die niet over de logica gaan maar over de
/// repository: de tabel in `docs/CHECKS.md` moet werkelijk bestaan en de
/// gedocumenteerde vorm dragen. Zonder die twee zou de poort met een lege
/// tabel evengoed groen kunnen staan zodra iemand hem per ongeluk weghaalt.
void main() {
  group('parseToolchain', () {
    test('leest versie, kanaal en herkomst uit de machine-uitvoer', () {
      final t = parseToolchain('''
{
  "frameworkVersion": "3.44.2",
  "channel": "[user-branch]",
  "repositoryUrl": "unknown source",
  "frameworkRevision": "c9a6c484230f8b5e408ec57be1ef71dee1e77020",
  "dartSdkVersion": "3.12.2"
}
''');
      expect(t, isNotNull);
      expect(t!.version, '3.44.2');
      expect(t.channel, '[user-branch]');
      expect(t.source, 'unknown source');
      expect(t.line, '3.44.2 • [user-branch] • unknown source');
    });

    test('de revisie telt niet mee', () {
      // Een hotfix verzet de revisie zonder dat er iets aan de
      // reproduceerbaarheid verandert. Zou die meetellen, dan stond de tabel om
      // de haverklap rood om niets en werd de poort uitgezet.
      String json(String revision) =>
          '{"frameworkVersion":"3.44.6","channel":"stable",'
          '"repositoryUrl":"https://github.com/flutter/flutter.git",'
          '"frameworkRevision":"$revision"}';

      expect(
        parseToolchain(json('aaa'))!.line,
        parseToolchain(json('bbb'))!.line,
      );
    });

    test('onleesbare of onvolledige uitvoer levert niets op', () {
      expect(parseToolchain('geen json'), isNull);
      expect(parseToolchain('[]'), isNull);
      // Eén ontbrekend veld is genoeg: half weten wat er draait is niet weten.
      expect(
        parseToolchain('{"frameworkVersion":"3.44.6","channel":"stable"}'),
        isNull,
      );
      expect(
        parseToolchain(
          '{"frameworkVersion":3,"channel":"stable",'
          '"repositoryUrl":"x"}',
        ),
        isNull,
      );
    });
  });

  group('parsePin', () {
    test('leest de flutter-regel en laat het asdf-kanaal weg', () {
      expect(parsePin('flutter 3.44.6-stable\n'), '3.44.6');
      expect(parsePin('dart 3.12.2\nflutter 3.44.6-stable\n'), '3.44.6');
      expect(parsePin('  flutter 3.44.7-stable  \n'), '3.44.7');
    });

    test('zonder flutter-regel is er geen pin', () {
      expect(parsePin('dart 3.12.2\n'), isNull);
      expect(parsePin(''), isNull);
    });
  });

  group('documentsToolchain', () {
    const running = Toolchain('3.44.7', 'stable', officialRepository);

    test('vindt de toolchain als de hele regel er staat', () {
      expect(
        documentsToolchain(
          '| Machine | `3.44.7 • stable • $officialRepository` | matches |',
          running,
        ),
        isTrue,
      );
    });

    test('losse velden in verschillende rijen tellen niet', () {
      // Dit is de reden dat er op de hele regel wordt gezocht en niet op de
      // drie velden apart: anders zou een tabel "kloppen" doordat het
      // versienummer in de ene rij staat en het kanaal in een andere.
      expect(
        documentsToolchain(
          '| A | `3.44.7 • [user-branch] • unknown source` |\n'
          '| B | `3.40.0 • stable • $officialRepository` |',
          running,
        ),
        isFalse,
      );
    });

    test('een lege of andere tabel is niet genoeg', () {
      expect(documentsToolchain('', running), isFalse);
      expect(
        documentsToolchain('| CI | `3.44.6 • stable • x` |', running),
        isFalse,
      );
    });
  });

  group('toolchainProblems', () {
    test('de gepinde officiële stable is in orde', () {
      expect(
        toolchainProblems(
          const Toolchain('3.44.7', 'stable', officialRepository),
          '3.44.7',
        ),
        isEmpty,
      );
    });

    test('een onofficieel kanaal is fataal', () {
      final p = toolchainProblems(
        const Toolchain('3.44.7', '[user-branch]', officialRepository),
        '3.44.7',
      );
      expect(p, hasLength(1));
      expect(p.single, contains('kanaal'));
    });

    test('een onbekende herkomst is fataal', () {
      final p = toolchainProblems(
        const Toolchain('3.44.7', 'stable', 'unknown source'),
        '3.44.7',
      );
      expect(p, hasLength(1));
      expect(p.single, contains('herkomst'));
    });

    test('een andere versie dan de pin is fataal — ook één patch', () {
      // Dit is de eis die eerder bewust níét hard was. Hij is het nu wel:
      // `dart format` reflowt tussen releases, dus een groene opmaakpoort op
      // 3.44.6 zegt niets over wat CI op 3.44.7 doet.
      final p = toolchainProblems(
        const Toolchain('3.44.6', 'stable', officialRepository),
        '3.44.7',
      );
      expect(p, hasLength(1));
      expect(p.single, contains('3.44.6'));
      expect(p.single, contains('3.44.7'));
    });

    test('zonder pin valt er niets te toetsen, en dat is zelf de fout', () {
      final p = toolchainProblems(
        const Toolchain('3.44.7', 'stable', officialRepository),
        null,
      );
      expect(p, hasLength(1));
      expect(p.single, contains('.tool-versions'));
    });

    test('alle drie de gebreken worden in één keer gemeld', () {
      // Wie een toolchain moet vervangen wil in één keer weten wat eraan
      // mankeert, niet drie runs lang één regel per keer.
      expect(
        toolchainProblems(
          const Toolchain('3.44.2', '[user-branch]', 'unknown source'),
          '3.44.7',
        ),
        hasLength(3),
      );
    });
  });

  group('de repository zelf', () {
    test('docs/CHECKS.md draagt de tabel waar de poort op leunt', () {
      final doc = File('docs/CHECKS.md').readAsStringSync();
      expect(
        doc,
        contains('Toolchains of record'),
        reason: 'de poort verwijst de lezer naar deze kop',
      );
      // Minstens één rij in de gedocumenteerde vorm, anders zou de poort
      // groen kunnen staan op een tabel die niets meer bevat.
      expect(
        RegExp(r'`\d+\.\d+\.\d+ • .+ • .+`').hasMatch(doc),
        isTrue,
        reason: 'geen enkele rij heeft de vorm `versie • kanaal • herkomst`',
      );
    });

    test('.tool-versions pint een flutter-versie', () {
      expect(parsePin(File('.tool-versions').readAsStringSync()), isNotNull);
    });
  });
}
