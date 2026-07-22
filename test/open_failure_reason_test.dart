import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Waaróm een bestand niet openging (#646).
///
/// De melding was "Kon dit bestand niet openen." — en dat stond voor vier heel
/// verschillende dingen: het bestand bestaat niet meer, het is te groot, het is
/// geen tekst, of de markdown is afgebroken. Voor een product dat om Markdown
/// draait is dat mager: de gebruiker weet zo niet of hij het verkeerde bestand
/// koos, of dat er iets stuk is, of dat hij iets kán doen.
///
/// Het venijn zat in de vertaling tussen de lagen. `FileService.openDeckDetailed`
/// gaf de reden al terug — [OpenFailure] onderscheidt zes gevallen — maar de
/// state-laag gooide hem weg en maakte er één `OpenResult.unreadable` van. Het
/// antwoord was dus twee lagen lager gewoon bekend.
///
/// Deze test gaat over die doorgifte. Dat de schil er de juiste zin bij zoekt,
/// staat in `shell_actions.dart` en is één `switch`; dat er niets *verzonnen*
/// wordt wanneer de oorzaak onbekend is, is hier de belangrijkste toets.
void main() {
  late Directory temp;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    temp = Directory.systemTemp.createTempSync('open_failure');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  /// Opent [path] in een verse container en geeft de vastgelegde reden terug.
  Future<OpenFailure?> reasonFor(String path) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(tabsProvider.notifier).openFileByPath(path);
    return container.read(openFailureProvider);
  }

  test(
    'een bestand dat er niet meer is, zegt dat het er niet meer is',
    () async {
      // Het gewoonste geval: een presentatie uit de recente lijst die verplaatst
      // of verwijderd is. Daar is "kon niet openen" het minst behulpzaam.
      expect(
        await reasonFor('${temp.path}/verdwenen.md'),
        OpenFailure.notFound,
      );
    },
  );

  test('een binair bestand wordt als onleesbaar herkend', () async {
    // Geen geldige UTF-8. De gebruiker koos iets wat geen tekst is — dan hoort
    // de melding te zeggen wat OciDeck wél opent.
    final pad = '${temp.path}/plaatje.md';
    File(pad).writeAsBytesSync([0xff, 0xfe, 0x00, 0x01, 0x02]);

    expect(await reasonFor(pad), isNot(OpenFailure.notFound));
    expect(await reasonFor(pad), isNotNull, reason: 'reden moet vastliggen');
  });

  test(
    'een leesbaar bestand dat geen presentatie is, houdt zijn eigen uitkomst',
    () async {
      // Dit geval had al een eigen melding en houdt die: hier gaat het erom dat
      // het niet stilletjes in de nieuwe, algemenere afhandeling verdwijnt.
      final pad = '${temp.path}/gewoon.md';
      File(pad).writeAsStringSync('# Zomaar een notitie\n\nGeen marp-kop.\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final uitkomst = await container
          .read(tabsProvider.notifier)
          .openFileByPath(pad);

      expect(uitkomst, OpenResult.notAPresentation);
      expect(container.read(openFailureProvider), OpenFailure.notPresentation);
    },
  );

  test('een geslaagde open laat geen oude reden achter', () async {
    // De valkuil van een provider die een reden onthoudt: na een mislukking
    // gevolgd door een geslaagde open zou de vólgende fout een verklaring
    // krijgen die niet van hem is. Daarom wist het openpad hem vooraf.
    final goed = '${temp.path}/deck.md';
    File(
      goed,
    ).writeAsStringSync('---\nmarp: true\n---\n\n# Titel\n\nInhoud.\n');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final tabs = container.read(tabsProvider.notifier);

    await tabs.openFileByPath('${temp.path}/verdwenen.md');
    expect(container.read(openFailureProvider), OpenFailure.notFound);

    await tabs.openFileByPath(goed);
    expect(
      container.read(openFailureProvider),
      isNull,
      reason: 'een reden van vorige keer wijst de verkeerde kant op',
    );
  });

  test('een te groot bytes-open legt de reden vast', () async {
    // Het bytes-pad (web-picker, sleepactie) stelt dit zelf vast; daar is geen
    // FileService die het al wist.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final teGroot = utf8.encode('x' * (FileService.maxDeckMarkdownBytes + 1));
    await container
        .read(tabsProvider.notifier)
        .openDeckFromBytes(teGroot, 'groot.md');

    expect(container.read(openFailureProvider), OpenFailure.tooLarge);
  });
}
