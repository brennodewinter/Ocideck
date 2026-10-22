// De typologie achter de transcriptiegrens (#2510, TRANSCRIPTION.md §4.2–4.4).
// Geen mock-werk: deze toetsen pinnen wat de contracttypen beloven — de
// fouttaxonomie is uitputtend en diagnoseerbaar, een resultaat voegt
// segmenten samen zonder er iets bij te verzinnen, en "afwezig" is overal
// een expliciete toestand (null/false), nooit een weggelaten default.
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';
import 'package:ocideck/services/transcription/transcription_errors.dart';

void main() {
  group('fouttaxonomie (§4.4)', () {
    test('elke variant draagt zijn eigen benoemde vervolgstap', () {
      // De switch is uitputtend over het sealed type: voegt er iemand een
      // variant toe, dan compileert deze toets niet meer — precies wat de
      // grens eist voordat de UI een stap koppelt.
      String benoem(TranscriptionError e) => switch (e) {
        PermissionDenied() => 'vraag opnieuw om toestemming',
        SourceUnavailable() => 'kies een andere bron',
        UnsupportedSource() => 'leg uit waarom deze bron niet kan',
        DecodeFailed() => 'kies een andere route of exporteer eerst',
        EngineUnavailable() => 'installeer of kies een engine',
        CapacityExceeded() => 'korter opnemen of andere route',
        ServerRefused() => 'controleer endpoint en verbinding',
        ConsentRequired() => 'vraag expliciete toestemming',
        Cancelled() => 'geen melding — gebruiker stopte bewust',
        IoFailed() => 'ruimte of pad oplossen',
      };

      // Bewust niet-const: een const-constructie voert de constructor niet
      // uit — de coverage-vloer telt hem dan nooit.
      final variants = <TranscriptionError>[
        PermissionDenied('mic geweigerd'),
        SourceUnavailable('brug weg'),
        UnsupportedSource('rdp'),
        DecodeFailed('codec'),
        EngineUnavailable('model ontbreekt'),
        CapacityExceeded('mem-budget'),
        ServerRefused('tls'),
        ConsentRequired('deelnemers'),
        Cancelled('stop'),
        IoFailed('schijf'),
      ];
      expect(variants, hasLength(10));
      for (final v in variants) {
        expect(benoem(v), isNotEmpty, reason: '$v heeft geen stap');
      }
    });

    test('toString vermeldt type en boodschap, nooit ruwe inhoud', () {
      final e = EngineUnavailable('whisper-small ontbreekt');
      expect(e.toString(), contains('EngineUnavailable'));
      expect(e.toString(), contains('whisper-small ontbreekt'));
    });
  });

  group('enginecontract (§4.2)', () {
    test('EngineKind kent de drie toestemmingsregimes', () {
      expect(EngineKind.values, hasLength(3));
      expect(
        EngineKind.values,
        containsAll([
          EngineKind.local,
          EngineKind.batchServer,
          EngineKind.liveServer,
        ]),
      );
    });

    test('capaciteiten zijn afwezig tenzij de engine ze echt levert', () {
      final caps = EngineCapabilities();
      expect(caps.languages, isEmpty);
      expect(caps.timestamps, isFalse);
      expect(caps.diarization, isFalse);
      expect(caps.streaming, isFalse);
      expect(caps.requiresModel, isNull);
    });

    test('een resultaat is zijn segmenten aan elkaar — niets erbij', () {
      final r = TranscriptResult(
        segments: [
          TranscriptSegment(text: 'hallo ', start: Duration.zero),
          TranscriptSegment(text: 'wereld', speaker: 'A'),
        ],
      );
      expect(r.text, 'hallo wereld');
      // Tijdstempel en spreker zijn per segment afwezig-bewijsbaar.
      expect(r.segments[0].speaker, isNull);
      expect(r.segments[1].start, isNull);
      // Een engine die niets dan platte tekst had, levert geen segmenten.
      expect(TranscriptResult().text, '');
    });

    test('opties en verwijzingen dragen alleen wat de grens belooft', () {
      expect(TranscriptionOptions().language, isNull);
      expect(TranscriptionOptions(language: 'nl').language, 'nl');
      expect(AudioRef('/tmp/x.m4a').path, '/tmp/x.m4a');
      final p = PartialTranscript(
        text: 'voorlopig',
        offset: const Duration(seconds: 4),
      );
      expect(p.offset, const Duration(seconds: 4));
    });
  });
}
