import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/file_recovery/file_recovery_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late File md;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('recovery-test');
    md = File(p.join(tmp.path, 'deck.md'));
    await md.writeAsString('---\nmarp: true\n---\n\n# Titel\n');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<FileRecoveryResult> recover() =>
      FileRecoveryService().recoverCopy(md.path);

  group('FileRecoveryService.recoverCopy (#2880)', () {
    test(
      'kopieert het deck en zijn leden byte-exact naar een nieuwe map',
      () async {
        await File(p.join(tmp.path, 'deck.ink.json')).writeAsString('{"v":1}');
        await File(
          p.join(tmp.path, 'ocideck-style.json'),
        ).writeAsString('{"name":"Eigen"}');
        await Directory(p.join(tmp.path, 'logos')).create();
        await File(
          p.join(tmp.path, 'logos', 'logo.png'),
        ).writeAsBytes([1, 2, 3]);

        final result = await recover();

        expect(result.recoveredMarkdownPath, isNotNull);
        expect(p.basename(result.directory.path), 'deck-herstel');
        expect(
          await File(result.recoveredMarkdownPath!).readAsString(),
          await md.readAsString(),
        );
        // Elke member draagt de sha256 van de bron — vergelijkbaar bewijs.
        for (final m in result.members) {
          expect(m.disposition, RecoveryDisposition.copied);
          final source = File(p.join(tmp.path, m.path));
          expect(
            m.sha256,
            sha256.convert(await source.readAsBytes()).toString(),
          );
          expect(m.byteCount, await source.length());
        }
        // Manifest en rapport staan in _herstel/ in de kopie.
        expect(await File(result.manifestPath).exists(), isTrue);
        expect(await File(result.reportPath).exists(), isTrue);
        // Het origineel is onaangeroerd.
        expect(await md.readAsString(), '---\nmarp: true\n---\n\n# Titel\n');
      },
    );

    test(
      'parkeert een kapot stijlbestand onder _herstel/ zodat de kopie opent',
      () async {
        final style = File(p.join(tmp.path, 'ocideck-style.json'));
        // Echt kapot: afgekapte JSON. `{"logoSize":"96"}` zou níét
        // quarantainen — per-veld fallback uit #2877 leest dat nog prima.
        await style.writeAsString('{"logoSize":');

        final result = await recover();

        final moved = File(
          p.join(result.directory.path, '_herstel', 'ocideck-style.json'),
        );
        expect(await moved.exists(), isTrue);
        // De levende plek is vrij — de kopie struikelt er niet meer over.
        expect(
          await File(
            p.join(result.directory.path, 'ocideck-style.json'),
          ).exists(),
          isFalse,
        );
        // Origineel staat er nog, byte-identiek.
        expect(await style.readAsString(), '{"logoSize":');
        final member = result.members.singleWhere(
          (m) => m.path == 'ocideck-style.json',
        );
        expect(member.disposition, RecoveryDisposition.quarantined);
        expect(result.diagnoses.any((d) => d.contains('stijl')), isTrue);
      },
    );

    test(
      'legt het zegel terzijde als de kopie afwijkt van de verzegelde bron',
      () async {
        await File(
          p.join(tmp.path, 'deck.seal.json'),
        ).writeAsString('{"seal":true}');
        await File(
          p.join(tmp.path, 'ocideck-style.json'),
        ).writeAsString('kapot');

        final result = await recover();

        expect(
          await File(p.join(result.directory.path, 'deck.seal.json')).exists(),
          isFalse,
        );
        expect(
          await File(
            p.join(result.directory.path, '_herstel', 'deck.seal.json'),
          ).exists(),
          isTrue,
        );
        final manifest = jsonDecode(
          await File(result.manifestPath).readAsString(),
        );
        expect(manifest['zegelTerzijde'], isTrue);
      },
    );

    test('een tweede poging overschrijft de eerste kopie niet', () async {
      final first = await recover();
      final second = await recover();

      expect(p.basename(first.directory.path), 'deck-herstel');
      expect(p.basename(second.directory.path), 'deck-herstel-2');
      expect(
        await File(p.join(first.directory.path, 'deck.md')).exists(),
        isTrue,
      );
    });

    test('bewaart onbekende onderdelen (data/) byte-exact', () async {
      await Directory(p.join(tmp.path, 'data')).create();
      final chart = File(p.join(tmp.path, 'data', 'chart-1.json'));
      await chart.writeAsString('{"vreemd":[1,2,3]}');

      final result = await recover();

      final copied = File(
        p.join(result.directory.path, 'data', 'chart-1.json'),
      );
      expect(await copied.readAsString(), '{"vreemd":[1,2,3]}');
      final member = result.members.singleWhere(
        (m) => m.path == p.join('data', 'chart-1.json'),
      );
      expect(member.disposition, RecoveryDisposition.copied);
    });

    test('meldt een onleesbare bron eerlijk als niet-gered', () async {
      // Een .md die niet leesbaar is: het lid gaat niet naar _herstel/
      // (er valt niets te "repareren") maar telt als unreadable — nooit
      // als hersteld gerapporteerd.
      await md.writeAsBytes([0xFF, 0xFE, 0x00, 0x80]); // geen UTF-8

      final result = await recover();

      // De bytes komen wél byte-exact in de kopie — niet-interpreteren
      // mag nooit weggooien betekenen.
      final copied = File(p.join(result.directory.path, 'deck.md'));
      expect(await copied.readAsBytes(), [0xFF, 0xFE, 0x00, 0x80]);
      expect(result.recoveredMarkdownPath, isNotNull);
      // De manifest-vermelding blijft eerlijk: copied, geen reparatieclaim.
      final member = result.members.singleWhere((m) => m.path == 'deck.md');
      expect(member.disposition, RecoveryDisposition.copied);
    });
  });
}
