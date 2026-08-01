import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/models/asset_rights.dart';
import 'package:ocideck/services/asset_rights_repository_scanner.dart';
import 'package:ocideck/services/asset_rights_scanner.dart';
import 'package:ocideck/services/asset_rights_store.dart';
import 'package:ocideck/services/git/asset_rights_index.dart';
import 'package:path/path.dart' as p;

import 'git_forge_fake.dart';

Uint8List _png() {
  final image = img.Image(width: 2, height: 3);
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _jpegWithCopyright(String copyright) {
  final image = img.Image(width: 2, height: 3);
  image.exif.imageIfd['Copyright'] = copyright;
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  group('AssetRightsScanner', () {
    test(
      'meldt ontbrekend rechtenbewijs zonder juridische zekerheid',
      () async {
        final result = await const AssetRightsScanner().scan(
          _png(),
          filename: 'foto.png',
          now: DateTime.utc(2026, 8, 2),
        );

        expect(result.width, 2);
        expect(result.height, 3);
        expect(result.risk, AssetRightsRisk.review);
        expect(
          result.signals.map((s) => s.ruleId),
          contains('rights.missing_evidence'),
        );
        expect(result.signals.single.message, isNot(contains('inbreuk')));
      },
    );

    test('vindt ingebedde copyrightmetadata', () async {
      final result = await const AssetRightsScanner().scan(
        _jpegWithCopyright('Fotograaf Voorbeeld'),
        filename: 'foto.jpg',
        provenance: const AssetRightsProvenance(
          license: 'CC BY 4.0',
          licenseEvidence: 'https://example.test/licentie',
        ),
      );

      final signal = result.signals.single;
      expect(signal.ruleId, 'rights.embedded_notice');
      expect(signal.evidence['Copyright'], contains('Fotograaf Voorbeeld'));
    });

    test('markeert verlopen licentie als hoog risico', () async {
      final result = await const AssetRightsScanner().scan(
        _png(),
        filename: 'foto.png',
        provenance: AssetRightsProvenance(
          license: 'Stock',
          licenseEvidence: 'factuur-1',
          licenseExpiresAt: DateTime.utc(2025),
        ),
        now: DateTime.utc(2026),
      );

      expect(result.risk, AssetRightsRisk.high);
      expect(result.signals.single.ruleId, 'rights.license_expired');
    });
  });

  test(
    'afdoening verbergt alleen exact dezelfde signaalvingerafdruk',
    () async {
      final first = await const AssetRightsScanner().scan(
        _png(),
        filename: 'foto.png',
      );
      final signal = first.signals.single;
      final decided = first.copyWith(
        dispositions: [
          AssetRightsDisposition(
            signalKey: signal.key,
            status: AssetRightsDispositionStatus.accepted,
            reason: 'owned',
            decidedAt: DateTime.utc(2026, 8, 2),
          ),
        ],
      );

      expect(decided.openSignals, isEmpty);
      final changed = decided.copyWith(
        signals: [
          AssetRightsSignal(
            ruleId: signal.ruleId,
            risk: signal.risk,
            message: signal.message,
            fingerprint: 'ander',
          ),
        ],
      );
      expect(changed.openSignals, hasLength(1));
    },
  );

  test('codec round-tript auditgegevens', () async {
    final original = await const AssetRightsScanner().scan(
      _png(),
      filename: 'foto.png',
      provenance: const AssetRightsProvenance(
        creator: 'Maker',
        license: 'Eigen werk',
        licenseEvidence: 'DMS-1',
      ),
    );
    final decoded = AssetRightsAssessment.decode(original.encode());

    expect(decoded.sha256, original.sha256);
    expect(decoded.provenance.creator, 'Maker');
    expect(decoded.scannerVersion, AssetRightsScanner.version);
  });

  test('repositoriescan scant uniek en hergebruikt actuele sidecar', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck-rights-');
    addTearDown(() => temp.delete(recursive: true));
    final assets = Directory(p.join(temp.path, 'assets'))..createSync();
    final bytes = _png();
    final hash = sha256.convert(bytes).toString();
    File(p.join(assets.path, '$hash.png')).writeAsBytesSync(bytes);

    final scanner = const AssetRightsRepositoryScanner();
    final first = await scanner.scan(temp.path);
    final second = await scanner.scan(temp.path);

    expect(first.assessments, hasLength(1));
    expect(first.reused, 0);
    expect(second.reused, 1);
    final sidecar = AssetRightsStore(temp.path).fileFor(hash);
    expect(sidecar.existsSync(), isTrue);
    expect(
      jsonDecode(sidecar.readAsStringSync()),
      isA<Map<Object?, Object?>>(),
    );
  });

  test(
    'opeenvolgende beheerdersbesluiten behouden elkaars auditregel',
    () async {
      final assessment = await const AssetRightsScanner().scan(
        _png(),
        filename: 'foto.png',
      );
      final path = AssetRightsStore.repoPathFor(assessment.sha256);
      final repo = FakeRepo(
        branches: {'main': 'c0'},
        files: {path: Uint8List.fromList(utf8.encode(assessment.encode()))},
      );
      final index = RepoAssetRightsIndex(
        forge: FakeForge(repo),
        branch: 'main',
      );
      final signal = assessment.signals.single;

      await index.decide(
        assessment,
        signal,
        status: AssetRightsDispositionStatus.accepted,
        reason: 'licensed',
        note: 'Dossier A',
      );
      await index.decide(
        assessment,
        signal,
        status: AssetRightsDispositionStatus.accepted,
        reason: 'false_positive',
        note: 'Controle B',
      );

      final stored = AssetRightsAssessment.decode(
        utf8.decode(repo.files[path]!),
      );
      expect(stored.dispositions, hasLength(2));
      expect(stored.dispositions.map((item) => item.note), [
        'Dossier A',
        'Controle B',
      ]);
    },
  );
}
