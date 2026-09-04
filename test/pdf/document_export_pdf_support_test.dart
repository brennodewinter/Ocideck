// Het schilwerk rond de PDF-export: de gebundelde terugvalsnede, de vertaalde
// teksten, en de zin die de gebruiker leest als er iets niet gezet kon worden.

import 'dart:async';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/pdf/document_pdf_blocks.dart';
import 'package:ocideck/widgets/parts/document_export_pdf_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l10n = AppLocalizations(const Locale('nl'));

  test('de echte documentexport sluit beide tekenrenderers aan', () {
    // Een renderer in de PDF-bouwer helpt niet wanneer het bewerkscherm hem
    // niet doorgeeft. Deze bronpoort bewaakt precies die productiekoppeling;
    // de native bestandskiezer maakt de route niet betrouwbaar aanstuurbaar in
    // een widgettest.
    final source = File(
      'lib/widgets/document_editor_screen.dart',
    ).readAsStringSync();
    // Op `await` en niet op `return`: sinds #1902 vangt het bewerkscherm de
    // uitkomst op om een geweigerde browserdownload te kunnen melden. De
    // aanroep is dezelfde; alleen wat ermee gebeurt is veranderd.
    final start = source.indexOf('await writeDocumentExport(');
    final end = source.indexOf('\n  );', start);
    // Vóór het snijden, niet erna: anders valt deze toets om met een
    // RangeError over een index in plaats van te zeggen dat de aanroep niet
    // gevonden is.
    expect(
      start,
      isNot(-1),
      reason: 'aanroep van writeDocumentExport niet gevonden',
    );
    expect(end, isNot(-1), reason: 'einde van de aanroep niet gevonden');
    final call = source.substring(start, end);
    expect(call, contains('renderMermaid: renderMermaidForPdf'));
    expect(call, contains('renderMath: renderMathForPdf'));
  });

  test('de gebundelde terugvalfonts zijn te laden', () async {
    // Zonder deze fonts blijft de PDF bij Latin-1 en verdwijnt elk Pools,
    // Grieks of Cyrillisch teken uit de tekstlaag. Dat de bestanden
    // daadwerkelijk mee worden gebundeld, is dus geen detail maar de
    // voorwaarde — en dat het er drie zijn evenmin: de tweede draagt de pijlen
    // en de derde de wiskunde (#1987).
    final fonts = await loadPdfFallbackFonts();
    expect(fonts, hasLength(3));
    for (final font in fonts) {
      expect(font.lengthInBytes, greaterThan(1000));
    }
  });

  test('elk soort letterlijk blok krijgt een eigen aanduiding', () {
    final labels = documentPdfLabels(l10n);
    final all = PdfVerbatimKind.values.map(labels.labelFor).toList();
    expect(all.toSet(), hasLength(PdfVerbatimKind.values.length));
    for (final label in all) {
      expect(label.trim(), isNotEmpty);
    }
  });

  test('de melding noemt de tekens die ontbreken', () {
    // "Sommige tekens" laat de gebruiker zoeken in zijn eigen document.
    final message = unsupportedCharactersMessage(l10n, {'日'.runes.first});
    expect(message, contains('日'));
    expect(message, contains('HTML'));
  });

  test('een lange lijst tekens wordt afgekapt, niet uitgespeld', () {
    final many = List.generate(40, (i) => 0x4E00 + i).toSet();
    final message = unsupportedCharactersMessage(l10n, many);
    expect(message, contains('…'));
    // Ruim onder wat er anders in zou staan: de boodschap is dan al aangekomen.
    expect(message.length, lessThan(300));
  });

  group('wachttijd voor een tekening', () {
    test('een renderer die nooit antwoordt levert niets op', () async {
      // Het geval dat er werkelijk toe doet: een verzoek dat de wachtrij nooit
      // verlaat omdat de verborgen WebView niet gemonteerd is. Het plafond van
      // de renderer zelf raakt dat nooit. Zonder dít plafond hangt de export op
      // één diagram — en een export die blijft hangen is erger dan een diagram
      // dat als bron in het bestand komt.
      final nooit = Completer<String?>();
      final uitkomst = await graphicWithinBudget(
        nooit.future,
        limit: const Duration(milliseconds: 20),
      );
      expect(uitkomst, isNull);
    });

    test('een renderer die op tijd antwoordt komt er gewoon door', () async {
      expect(
        await graphicWithinBudget(
          Future.value('<svg/>'),
          limit: const Duration(seconds: 5),
        ),
        '<svg/>',
      );
    });
  });

  group('de melding bij een tabel die niet past (#1789)', () {
    test('enkelvoud en meervoud lopen niet door elkaar', () {
      expect(tablesTooWideMessage(l10n, 1), contains('Eén tabel past niet'));
      final drie = tablesTooWideMessage(l10n, 3);
      expect(drie, contains('3 tabellen passen niet'));
      expect(drie, isNot(contains('{n}')), reason: 'plaatshouder blijft staan');
    });

    test('noemt wat er verloren gaat en wat de lezer eraan kan doen', () {
      // "Deze tabel past niet" is een oordeel waar niemand iets mee kan. De
      // melding noemt daarom de schade (waarden middenin afgebroken) én de twee
      // vormen die wél passen.
      final bericht = tablesTooWideMessage(l10n, 1);
      expect(bericht, contains('IP-adressen'));
      expect(bericht, contains('onder elkaar'));
    });
  });

  test('de documentexport geeft de tabelwaarschuwing door aan de schil', () {
    // Zelfde bronpoort als hierboven: een melding die de exportdienst wél
    // vuurt maar het bewerkscherm niet doorgeeft, bereikt niemand.
    final source = File(
      'lib/widgets/document_editor_screen.dart',
    ).readAsStringSync();
    expect(source, contains('onPdfTablesTooWide:'));
    expect(source, contains('warnAboutTablesTooWide('));
  });
}
