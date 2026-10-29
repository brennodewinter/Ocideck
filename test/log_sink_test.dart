// Wat `utils/log.dart` aan het logbestand doorgeeft (#2618): de vorm van een
// regel, de padsanering, de rem op herhaling en de werklabels.
//
// Het logbestand is iets wat een gebruiker met ons deelt. Wat hier fout gaat,
// staat dus op schijf én in een e-mail: een bestandsnaam, een gebruikersnaam,
// of — via een FormatException — de inhoud van een dia.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/log.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';

class _Lines implements LogSink {
  final lines = <String>[];

  @override
  void write(String line) => lines.add(line);

  @override
  Future<void> close() async {}
}

void main() {
  late _Lines sink;

  setUp(() {
    sink = _Lines();
    installLogSink(sink);
  });

  tearDown(() => installLogSink(null));

  group('redactPaths', () {
    test('een POSIX-pad wordt een hash met de extensie', () {
      final out = redactPaths(
        'saveToGit: /Users/jan/Documents/Ontslag Jan.md niet opgeslagen',
      );
      expect(out, startsWith('saveToGit: <pad#'));
      expect(out, isNot(contains('jan')));
      expect(out, isNot(contains('Ontslag')));
    });

    test('hetzelfde pad geeft dezelfde hash, een ander pad een andere', () {
      final a = redactPaths('x /Users/jan/a.png');
      final b = redactPaths('y /Users/jan/a.png');
      final c = redactPaths('x /Users/jan/b.png');
      expect(a.substring(2), b.substring(2));
      expect(a, isNot(c));
      expect(a, endsWith('.png>'));
    });

    test('Windows, UNC, ~ en file:-URI', () {
      for (final path in [
        r'C:\Users\jan\Documents\geheim.docx',
        'C:/Users/jan/geheim.docx',
        r'\\server\share\jan\geheim.docx',
        '~/Documents/geheim.docx',
        'file:///Users/jan/geheim.docx',
        'file:///C:/Users/jan/geheim.docx',
      ]) {
        final out = redactPaths('open: $path');
        expect(out, isNot(contains('jan')), reason: path);
        expect(out, isNot(contains('geheim')), reason: path);
        expect(out, contains('.docx>'), reason: path);
      }
    });

    test(
      'een pad tussen aanhalingstekens laat de rest van de melding staan',
      () {
        final error = FileSystemException(
          'Cannot open file',
          '/Users/jan/Proefpresentatie (2)/deck.md',
          const OSError('No such file or directory', 2),
        );
        final out = redactPaths('$error');
        expect(out, isNot(contains('jan')));
        expect(out, isNot(contains('deck.md')));
        expect(out, contains('No such file or directory'));
        expect(out, contains('errno = 2'));
      },
    );

    test('een pad tussen haakjes sluit bij het haakje', () {
      expect(
        redactPaths('DiskTraces: map niet verwijderd (/tmp/ocideck/x) — later'),
        matches(
          RegExp(r'^DiskTraces: map niet verwijderd \(<pad#\w{8}>\) — later$'),
        ),
      );
    });

    test('URL\'s, MIME-typen, breuken en datums blijven staan', () {
      for (final keep in [
        'GET https://pawprint.vigilis.online/LibreKAT/Ocideck/issues',
        'type image/png, verhouding 16/9',
        'datum 28/10/2026, en/of',
        'OciDeck/0.7.3',
      ]) {
        expect(redactPaths(keep), keep);
      }
    });
  });

  group('regels naar de sink', () {
    test('een regel draagt tijd, niveau, melding en gesaneerde fout', () {
      logWarning('Outbox: wachtende commit onleesbaar', StateError('stuk'));
      expect(sink.lines, hasLength(1));
      expect(
        sink.lines.single,
        matches(
          RegExp(
            r'^\d{4}-\d\d-\d\dT[\d:.]+ WARN Outbox: wachtende commit '
            r'onleesbaar \| Bad state: stuk\n$',
          ),
        ),
      );
    });

    test('een FormatException brengt de ontlede bron niet mee', () {
      logError(
        'parse: dia-veld',
        const FormatException(
          'Unexpected character',
          'GEHEIM: Jan de Vries',
          7,
        ),
      );
      expect(sink.lines.single, contains('Unexpected character (positie 7)'));
      expect(sink.lines.single, isNot(contains('GEHEIM')));
      expect(sink.lines.single, isNot(contains('Vries')));
    });

    test('een pad in de fout én in de melding wordt onherkenbaar', () {
      logError(
        'readImageDimensions: failed to read /Users/jan/foto.jpg',
        const PathNotFoundException(
          '/Users/jan/foto.jpg',
          OSError('not found', 2),
          'Cannot open file',
        ),
      );
      expect(sink.lines.single, isNot(contains('jan')));
      expect(sink.lines.single, contains('.jpg>'));
    });

    test('een stack blijft bij de bovenste frames', () {
      final frames = List.generate(
        40,
        (i) => '#$i      f$i (package:x/y.dart:$i)',
      );
      logError('x', StateError('y'), StackTrace.fromString(frames.join('\n')));
      final lines = sink.lines.single.trimRight().split('\n');
      expect(lines, hasLength(1 + 12));
      expect(lines.last, contains('f11'));
    });

    test('een lange foutmelding wordt afgekapt', () {
      logWarning('x', 'a' * 5000);
      expect(sink.lines.single.length, lessThan(1200));
    });

    test('herhaling vult het bestand niet', () {
      for (var i = 0; i < 250; i++) {
        logWarning('image: niet gevonden');
      }
      // Twintig vrij, daarna alleen de honderdste en tweehonderdste met telling.
      expect(sink.lines, hasLength(22));
      expect(sink.lines[20], contains('(100×)'));
      expect(sink.lines[21], contains('(200×)'));
    });

    test('een andere melding telt apart', () {
      for (var i = 0; i < 30; i++) {
        logWarning('a');
      }
      logWarning('b');
      expect(sink.lines.where((l) => l.contains(' b')), hasLength(1));
    });

    test('een mijlpaal draagt de tijd sinds de start', () {
      logMilestone('eerste frame');
      expect(
        sink.lines.single,
        matches(RegExp(r' INFO opstart: eerste frame \(\+\d+ ms\)\n$')),
      );
    });

    test('een sink die gooit, laat de aanroeper heel', () {
      installLogSink(_Throwing());
      expect(() => logError('x', StateError('y')), returnsNormally);
      expect(closeLog, returnsNormally);
    });
  });

  group('werklabels', () {
    test('alleen de labels vanaf het gevraagde moment, elk één keer', () async {
      noteWork('oud');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final since = logClockMs;
      noteWork('gezichtsscan');
      noteWork('documentsync');
      noteWork('gezichtsscan');
      expect(workSince(since), ['gezichtsscan', 'documentsync']);
    });

    test('de zware paden zetten hun label', () {
      final since = logClockMs;
      MarkdownQuillCodec.markdownFromDocument(
        MarkdownQuillCodec.documentFromMarkdown('# Kop\n\ntekst'),
      );
      expect(workSince(since), [
        'Markdown → visuele editor',
        'visuele editor → Markdown',
      ]);
    });

    test('de ring vergeet de oudste', () {
      final since = logClockMs;
      for (var i = 0; i < 40; i++) {
        noteWork('w$i');
      }
      final seen = workSince(since);
      expect(seen, hasLength(16));
      expect(seen.first, 'w24');
      expect(seen.last, 'w39');
    });
  });
}

class _Throwing implements LogSink {
  @override
  void write(String line) => throw StateError('schijf vol');

  @override
  Future<void> close() => Future.error(StateError('schijf vol'));
}
