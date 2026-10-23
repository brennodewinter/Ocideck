// De modelcatalogus (#2512) als bewuste, kleine lijst: elke rij is
// compleet en klopt met zichzelf — zonder die eigenschappen is "downloaden
// met hash" een schijnzekerheid.
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/whisper_model.dart';

void main() {
  group('catalogusintegriteit', () {
    test('id\'s zijn uniek en elke rij is volledig', () {
      final ids = <String>{};
      for (final m in whisperModelCatalog) {
        expect(ids.add(m.id), isTrue, reason: 'dubbel id ${m.id}');
        expect(m.fileName, startsWith('ggml-'));
        expect(m.fileName, endsWith('.bin'));
        // De naam mag nooit uit het ophaal- of opslagpad ontsnappen.
        expect(m.fileName, isNot(contains('/')));
        expect(m.fileName, isNot(contains('..')));
        // Een hash is 64 hex-tekens; minder is geen pin maar een suggestie.
        expect(m.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(m.downloadBytes, greaterThan(0));
        expect(m.diskBytes, m.downloadBytes);
        expect(m.tier, isIn(['light', 'balanced', 'accurate']));
      }
      expect(
        ids.length,
        greaterThanOrEqualTo(2),
        reason:
            'het issue eist minstens een klein meertalig model én '
            'large-v3-turbo/large-v3 waar haalbaar',
      );
    });

    test('url\'s pinnen op de repository-revisie, niet op main', () {
      for (final m in whisperModelCatalog) {
        final url = m.url;
        expect(url.scheme, 'https');
        expect(url.host, 'huggingface.co');
        expect(url.path, contains(whisperModelRepoRevision));
        expect(
          url.path,
          isNot(contains('/main/')),
          reason: 'een beweegbare ref is geen pin',
        );
        expect(url.path, endsWith('/${m.fileName}'));
      }
    });

    test(
      'de eis van het issue: small meertalig én large-v3-turbo staan er',
      () {
        expect(whisperModelById('small'), isNotNull);
        expect(whisperModelById('large-v3-turbo'), isNotNull);
        expect(whisperModelById('bestaat-niet'), isNull);
        expect(whisperModelById(null), isNull);
      },
    );
  });
}
