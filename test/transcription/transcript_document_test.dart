import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/transcript_document.dart';
import 'package:ocideck/services/transcription/transcript_marker.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';

const _provenance = TranscriptProvenance(
  title: 'vergadering 22 oktober',
  sourceLabel: 'opname-20261022-1403.m4a',
  audioRelPath: 'media/opname-20261022-1403.m4a',
  recordedAt: '2026-10-22 14:03',
  sourceKindLabel: 'microfoon',
  durationLabel: '0:41:12',
  engineLabel: 'whisper.cpp `base` (lokaal)',
  languageCode: 'nl',
);

void main() {
  group('buildTranscriptMarkdown', () {
    test('schrijft de contractvorm van §3.1', () {
      final md = buildTranscriptMarkdown(
        _provenance,
        'Eerste alinea van de tekst.\n',
      );
      expect(
        md,
        '<!-- transcript version=1 '
        'audio="media/opname-20261022-1403.m4a" -->\n'
        '# Transcript — vergadering 22 oktober\n'
        '\n'
        'Bron: [opname-20261022-1403.m4a](media/opname-20261022-1403.m4a)\n'
        'Opgenomen: 2026-10-22 14:03 · Bron: microfoon · Duur: 0:41:12\n'
        'Engine: whisper.cpp `base` (lokaal) · Taal: nl\n'
        '\n'
        '---\n'
        '\n'
        'Eerste alinea van de tekst.\n',
      );
      expect(detectTranscript(md), isA<ValidTranscript>());
    });

    test('zonder bewaarde audio: geen attribuut, geen link — tekst blijft', () {
      final md = buildTranscriptMarkdown(
        const TranscriptProvenance(
          title: 'gesprek',
          sourceLabel: 'opname-1.wav',
          recordedAt: '2026-10-22 14:03',
          sourceKindLabel: 'microfoon',
        ),
        'Tekst.\n',
      );
      expect(md, startsWith('<!-- transcript version=1 -->\n'));
      expect(md, contains('Bron: opname-1.wav\n'));
      expect(md, isNot(contains('media/')));
      expect(detectTranscript(md), isA<ValidTranscript>());
    });

    test('een callopname met gaten schrijft de ontbrekend-regel (#2530)', () {
      final md = buildTranscriptMarkdown(
        const TranscriptProvenance(
          title: 'vergadering 22 oktober',
          sourceLabel: 'Vergaderingsopname',
          recordedAt: '2026-10-22 14:03',
          sourceKindLabel: 'vergadering',
          gapsLabel:
              '~4 s bronaudio over 1 bron(nen) — track- of netwerkverlies '
              'tijdens de opname.',
        ),
        'Tekst.\n',
      );
      expect(
        md,
        contains(
          'Ontbrekend: ~4 s bronaudio over 1 bron(nen) — track- of '
          'netwerkverlies tijdens de opname.\n',
        ),
      );
      expect(detectTranscript(md), isA<ValidTranscript>());
    });
  });

  group('formatTranscriptBody', () {
    test('tijdstempels en sprekers alleen als de engine ze leverde', () {
      final body = formatTranscriptBody(const [
        TranscriptSegment(
          text: 'De eerste zin.',
          start: Duration(minutes: 4, seconds: 12),
          speaker: 'Spreker 1',
        ),
        TranscriptSegment(
          text: 'Het antwoord.',
          start: Duration(hours: 1, minutes: 4, seconds: 31),
          speaker: 'Spreker 2',
        ),
      ]);
      expect(
        body,
        '[0:04:12] **Spreker 1:** De eerste zin.\n'
        '[1:04:31] **Spreker 2:** Het antwoord.',
      );
    });

    test('zonder metadata is het gewone tekst', () {
      expect(
        formatTranscriptBody(const [TranscriptSegment(text: 'Alleen tekst.')]),
        'Alleen tekst.',
      );
    });
  });

  group('body-bereik en toepassing', () {
    final doc = buildTranscriptMarkdown(_provenance, 'Oude tekst.\n');

    test('transcriptBodyText leest de tekst onder de scheiding', () {
      expect(transcriptBodyText(doc)!.trim(), 'Oude tekst.');
    });

    test('applyTranscriptBody vervangt alleen de body', () {
      final next = applyTranscriptBody(doc, 'Nieuwe tekst.\n');
      expect(
        next,
        doc.replaceRange(
          doc.indexOf('\nOude tekst.'),
          doc.length,
          '\nNieuwe tekst.\n',
        ),
      );
      // Marker, kop en provenance staan byte-getrouw boven de scheiding.
      expect(next.startsWith(doc.substring(0, doc.indexOf('---'))), isTrue);
      expect(detectTranscript(next), isA<ValidTranscript>());
    });
  });

  group('planTranscriptUpdate', () {
    final doc = buildTranscriptMarkdown(_provenance, 'Uit de machine.\n');

    test('gelijke tekst: niets te doen', () {
      expect(
        planTranscriptUpdate(doc, 'Uit de machine.\n'),
        isA<TranscriptUnchanged>(),
      );
    });

    test('ongemoeide tekst mag stil vervangen worden (baseline-match)', () {
      final update = planTranscriptUpdate(
        doc,
        'Definitief.\n',
        baseline: 'Uit de machine.\n',
      );
      final apply = update as TranscriptApply;
      expect(apply.markdown, applyTranscriptBody(doc, 'Definitief.\n'));
    });

    test('aangepaste tekst vraagt de vergelijking', () {
      final edited = applyTranscriptBody(doc, 'Handmatig gecorrigeerd.\n');
      expect(
        planTranscriptUpdate(
          edited,
          'Definitief.\n',
          baseline: 'Uit de machine.\n',
        ),
        isA<TranscriptConflict>(),
      );
    });

    test('zonder baseline vraagt elke afwijking om bevestiging', () {
      expect(
        planTranscriptUpdate(doc, 'Andere uitslag.\n'),
        isA<TranscriptConflict>(),
      );
    });

    test('een document zonder scheiding is een conflict, geen overwrite', () {
      const orphan = '<!-- transcript version=1 -->\n# T\n\ntekst\n';
      expect(
        planTranscriptUpdate(orphan, 'Nieuw.\n'),
        isA<TranscriptConflict>(),
      );
    });

    test('boven de begrenzing wordt geweigerd', () {
      final big = 'x' * (maxTranscriptBodyBytes + 1);
      expect(planTranscriptUpdate(doc, big), isA<TranscriptTooLarge>());
    });
  });
}
