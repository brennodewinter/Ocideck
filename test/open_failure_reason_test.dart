import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/models/markdown_kind.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'io_fault.dart';

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

  test('een toegewezen stat is geen formaatfout: inaccessible, niet '
      'unreadable (#2876)', () async {
    // Het bestand staat er en is geldige Markdown — alleen de toegang
    // faalde. Dat melden als "geen leesbare tekst" stuurde de gebruiker
    // het bestand repareren terwijl de locatie het probleem was.
    final dir = Directory(temp.resolveSymbolicLinksSync());
    final pad = '${dir.path}/geweigerd.md';
    File(pad).writeAsStringSync('---\nmarp: true\n---\n\n# Titel\n\nInhoud.\n');

    final reden = await runWithFileFault(
      () => reasonFor(pad),
      targetPath: pad,
      failOn: {'length'},
    );

    expect(reden, OpenFailure.inaccessible);
  });

  test(
    'een fout die geen bekende categorie is, valt op het vangnet (#2887)',
    () async {
      // Elke I/O-stap in het openpad hoort zijn eigen uitkomst te kennen —
      // maar blijft er tóch een niet-filesystem-fout doorheen glippen, dan
      // is "kon niet openen" de eerlijke melding: het openFileByPath-vangnet
      // maakt er een uitkomst van in plaats van de fout te laten ontsnappen.
      final dir = Directory(temp.resolveSymbolicLinksSync());
      final pad = '${dir.path}/deck.md';
      File(
        pad,
      ).writeAsStringSync('---\nmarp: true\n---\n\n# Titel\n\nInhoud.\n');
      // De stijlsidecar wordt bij elke schijf-open aangeraakt; een StateError
      // (geen FileSystemException) glipt langs alle gerichte vangsten.
      final sidecar = '${dir.path}/ocideck-style.json';

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final result = await runWithFileFault(
        () => container.read(tabsProvider.notifier).openFileByPath(pad),
        targetPath: sidecar,
        failOn: {'exists'},
        error: StateError('geforceerde niet-IO-fout'),
      );

      expect(result, OpenResult.unreadable);
      expect(
        container.read(openFailureProvider),
        isNull,
        reason: 'een onbekende fout verzint geen reden',
      );
    },
  );

  test(
    'een sidecar die niet te staten is, blokkeert het openen niet',
    () async {
      // Dezelfde regel als bij een kapotte sidecar: een I/O-fout op de
      // bijlagen mag de presentatie er zelf niet meenemen.
      final dir = Directory(temp.resolveSymbolicLinksSync());
      final pad = '${dir.path}/deck.md';
      File(
        pad,
      ).writeAsStringSync('---\nmarp: true\n---\n\n# Titel\n\nInhoud.\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final result = await runWithFileFault(
        () => container.read(tabsProvider.notifier).openFileByPath(pad),
        targetPath: '${dir.path}/deck.ink.json',
        failOn: {'exists'},
      );

      expect(result, OpenResult.opened);
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
    'een leesbaar niet-marp .md opent als document (de poort is een router)',
    () async {
      // Vroeger een `notPresentation`-weigering; sinds de documentmodus opent zo'n
      // bestand als plat document (DOCUMENT_MODE.md §2) i.p.v. het te weigeren —
      // het verdwijnt dus niet stil, het krijgt juist een tabblad.
      final pad = '${temp.path}/gewoon.md';
      File(pad).writeAsStringSync('# Zomaar een notitie\n\nGeen marp-kop.\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final uitkomst = await container
          .read(tabsProvider.notifier)
          .openFileByPath(pad);

      expect(uitkomst, OpenResult.opened);
      expect(container.read(openFailureProvider), isNull);
      expect(container.read(tabsProvider).current!.kind, MarkdownKind.document);
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
