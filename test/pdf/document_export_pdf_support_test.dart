// Het schilwerk rond de PDF-export: de gebundelde terugvalsnede, de vertaalde
// teksten, en de zin die de gebruiker leest als er iets niet gezet kon worden.

import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/pdf/document_pdf_blocks.dart';
import 'package:ocideck/widgets/parts/document_export_pdf_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l10n = AppLocalizations(const Locale('nl'));

  test('het gebundelde terugvalfont is te laden', () async {
    // Zonder dit font blijft de PDF bij Latin-1 en verdwijnt elk Pools, Grieks
    // of Cyrillisch teken uit de tekstlaag. Dat het bestand daadwerkelijk mee
    // wordt gebundeld, is dus geen detail maar de voorwaarde.
    final font = await loadPdfFallbackFont();
    expect(font, isNotNull);
    expect(font!.lengthInBytes, greaterThan(1000));
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
}
