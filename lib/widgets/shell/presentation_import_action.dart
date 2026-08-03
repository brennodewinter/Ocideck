import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/import/bulk_import_runner.dart';
import '../../services/import/deck_builder.dart';
import '../../services/import/importers/import_failure.dart';
import '../../services/import/presentation_import_service.dart';
import '../../services/web_asset_store.dart';
import '../../state/deck_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/tabs_provider.dart';
import '../../utils/error_snackbar.dart';
import '../../utils/log.dart';
import '../../utils/user_facing_error.dart';
import '../dialogs/import_presentation_warning_dialog.dart';
import '../dialogs/import_decision_dialog.dart';
import '../dialogs/import_security_alarm_dialog.dart';
import '../dialogs/presentation_import_progress_dialog.dart';
import '../dialogs/presentation_import_queue_dialog.dart';

/// Eén gekozen bestand: de bytes plus de naam waaronder het gekozen werd.
typedef PickedPresentation = ({Uint8List bytes, String name});

/// Een presentatie (`.pptx`) importeren: waarschuwing → bestandskiezer →
/// conversie → open in een nieuwe tab. Cross-platform: de import werkt op
/// bytes, dus ook op web (geen `dart:io`). Het geopende deck is ongewijzigd
/// opgeslagen; wie het bewaart, kiest zelf een map — de waarschuwing raadt een
/// aparte importmap aan.
///
/// Kiest de gebruiker méér dan één bestand, dan splitst het pad: dan opent de
/// wachtrijdialoog (#772), die alles naar één doelmap wegschrijft in plaats van
/// tien tabbladen te openen. De grens ligt precies bij "meer dan één", want pas
/// dan bestaan de vragen die die dialoog stelt — volgorde en bestemming.
///
/// Bewust géén 1-op-1-kopie: OciDeck heeft een eenvoudiger diamodel, dus wat
/// niet past wordt een "niet overgenomen"-notitiedia. De melding telt hoeveel
/// dia's aandacht vragen.
///
/// [fileOverride] (één bestand) en [filesOverride] (een rij) slaan de
/// bestandskiezer over; dat is de testroute, net als `directoryOverride` bij de
/// OpenKAT-actie hiernaast — de statische `FilePicker` laat zich onder
/// `flutter test` niet aansturen. Alles ná de keuze is exact hetzelfde pad.
/// [targetDirectoryOverride] doet hetzelfde voor de mapkiezer in de wachtrij.
Future<void> importPresentation(
  BuildContext context,
  WidgetRef ref, {
  PickedPresentation? fileOverride,
  List<PickedPresentation>? filesOverride,
  String? targetDirectoryOverride,
}) async {
  final proceed = await showPresentationImportWarning(context);
  if (!proceed || !context.mounted) return;

  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);

  final picked =
      filesOverride ??
      (fileOverride != null ? [fileOverride] : await _pickPresentations(l10n));
  if (picked == null || picked.isEmpty || !context.mounted) return;

  if (picked.length > 1) {
    await _importQueue(context, ref, picked, targetDirectoryOverride);
    return;
  }
  final chosen = picked.first;

  // Twee fasen, met de vraag ertussen: lezen en classificeren, dán pas
  // beslissen wát er met de probleemdia's gebeurt, dán pas bouwen. Zo hoeft
  // het bestand niet twee keer geparseerd te worden (#812). Het lezen draait op
  // een worker-isolate met een klein annuleerbaar voortgangsvenster (#875), dus
  // de UI blijft reageren en de gebruiker kan een groot of vastgelopen bestand
  // stoppen.
  final prep = await PresentationImportProgressDialog.run(
    context,
    fileName: chosen.name,
    task: (report, cancel) async {
      try {
        // `translate: l10n.d` maakt de notitiedia's — die in het document van de
        // gebruiker worden opgeslagen — in zijn eigen taal (#806). De naad zit
        // op de bouwer; de service geeft hem door.
        return await PresentationImportService(
          builder: DeckBuilder(translate: l10n.d),
        ).prepare(
          chosen.bytes,
          filename: chosen.name,
          onProgress: report,
          cancel: cancel,
        );
      } catch (e, s) {
        logError('importPresentation', e, s);
        return const PreparedImportResult.failed(
          ImportFailure('Importeren mislukt.'),
        );
      }
    },
  );
  if (!context.mounted) return;

  // De gebruiker heeft het lezen gestopt: stil afbreken, er is niets gebouwd.
  if (prep.wasCancelled) return;

  final prepared = prep.prepared;
  if (prepared == null) {
    showErrorSnackBar(
      messenger,
      l10n,
      prep.failure == null
          ? l10n.d('Importeren mislukt.')
          : importFailureText(l10n, prep.failure!),
    );
    return;
  }

  final decisions = await ImportDecisionDialog.ask(
    context,
    prepared.problemSlides,
  );
  // `null` betekent: de gebruiker breekt de hele import af.
  if (decisions == null || !context.mounted) return;

  final BuiltDeck built;
  try {
    built = prepared.build(policies: decisions);
  } on WebAssetBudgetExceeded catch (e) {
    logWarning('importPresentation: webgeheugen vol', e);
    showErrorSnackBar(messenger, l10n, webAssetBudgetMessage(l10n));
    return;
  }
  // Fail-closed backstop (#876): draagt de gebouwde import na neutralisatie tóch
  // uitvoerbare inhoud, dan opent hij niet — hetzelfde alarm als bij een vreemd
  // bestand, in plaats van een deck dat bij het volgende openen wordt geweigerd.
  if (built.safetyFindings.isNotEmpty) {
    if (context.mounted) {
      await ImportSecurityAlarmDialog.show(
        context,
        ImportSecurityAlarm(path: chosen.name, findings: built.safetyFindings),
      );
    }
    return;
  }
  final deck = built.deck;

  final tabs = ref.read(tabsProvider.notifier);
  tabs.newEmptyTab();
  ref.read(tabsProvider).current!.deckNotifier.loadDeck(deck);

  final slides = deck.slides.length;
  final issues = built.problemSlides.length;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        issues == 0
            ? '${l10n.d('Presentatie geïmporteerd.')} '
                  '($slides ${l10n.d('dia’s')})'
            : '${l10n.d('Presentatie geïmporteerd; controleer de aandachtspunten.')} '
                  '($slides ${l10n.d('dia’s')}, $issues ${l10n.d('met verlies')})',
      ),
    ),
  );
}

/// De wachtrij voor meer dan één bestand: volgorde en doelmap in de dialoog,
/// daarna één melding met de uitkomst. De decks openen niet in tabbladen — dat
/// zou bij tien bestanden geen resultaat zijn maar een puinhoop — dus de
/// melding herhaalt waar ze staan, ook nadat de dialoog dicht is.
Future<void> _importQueue(
  BuildContext context,
  WidgetRef ref,
  List<PickedPresentation> picked,
  String? targetDirectoryOverride,
) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final summary = await PresentationImportQueueDialog.show(
    context,
    files: [
      for (final file in picked)
        BulkImportItem(bytes: file.bytes, name: file.name),
    ],
    fileService: ref.read(fileServiceProvider),
    initialDirectory:
        targetDirectoryOverride ?? ref.read(settingsProvider).homeDirectory,
  );
  if (summary == null || summary.outcomes.isEmpty) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        '${l10n.d('Presentaties geïmporteerd.')} '
        '(${summary.succeeded} ${l10n.d('geslaagd')}, '
        '${summary.failed} ${l10n.d('mislukt')}) '
        '${summary.targetDirectory}',
      ),
    ),
  );
}

/// De bestandskiezer, apart gehouden zodat de import zelf één rechte lijn
/// blijft. `null` betekent: niets gekozen; bestanden zonder bytes vallen af,
/// want zonder inhoud valt er niets om te zetten.
Future<List<PickedPresentation>?> _pickPresentations(
  AppLocalizations l10n,
) async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: presentationImportExtensions,
    withData: true,
    // Meer tegelijk mag: wie een stapel presentaties overzet, doet dat zelden
    // één voor één. Bij precies één blijft het gedrag ongewijzigd.
    allowMultiple: true,
    dialogTitle: l10n.d('Presentatie kiezen'),
  );
  if (picked == null) return null;
  return [
    for (final file in picked.files)
      if (file.bytes case final bytes?)
        (bytes: Uint8List.fromList(bytes), name: file.name),
  ];
}

/// Het menulabel voor de presentatie-import.
String presentationImportLabel(AppLocalizations l10n) =>
    l10n.d('Presentaties importeren…');

/// De bestandsextensies die de import kent (zonder punt). Eén bron voor de
/// bestandskiezer én voor de herkenning bij een mislukte "Openen": groeit een
/// importeur mee, dan groeien beide mee. Bewust formaat-loos in de teksten
/// eromheen, zodat er niets te herzien valt als er een formaat bij komt.
const presentationImportExtensions = ['pptx', 'odp', 'key'];

/// Herkent aan de bestandsnaam of dit een presentatie is die de import kan
/// omzetten. Gebruikt bij een mislukte "Openen": koos de gebruiker eigenlijk
/// een `.pptx`/`.odp`/`.key`, dan is een import de bedoeling — geen Markdown.
bool isImportablePresentationName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return false;
  return presentationImportExtensions.contains(
    name.substring(dot + 1).toLowerCase(),
  );
}

/// De uitweg die een mislukte "Openen" van een presentatie krijgt, in plaats
/// van een doodlopende melding. `null` als [sourceName] geen presentatie is —
/// dan blijft de gewone open-foutmelding staan.
///
/// Twee dingen: wát het is, en wát de gebruiker nu kan doen. Staat de module
/// Importeren aan ([importModuleAvailable]), dan is dat "importeer hem meteen"
/// ([startsImport] `true`). Staat hij uit, dan eerst aanzetten — de melding
/// wijst naar de instellingen in plaats van de module stil aan te zetten.
({String message, bool startsImport})? presentationOpenRescue(
  AppLocalizations l10n,
  String sourceName, {
  required bool importModuleAvailable,
}) {
  if (!isImportablePresentationName(sourceName)) return null;
  if (importModuleAvailable) {
    return (
      message: l10n.d(
        'Dit is een presentatie, geen Markdown-bestand. OciDeck kan hem importeren naar een nieuw deck.',
      ),
      startsImport: true,
    );
  }
  return (
    message: l10n.d(
      'Dit is een presentatie, geen Markdown-bestand. Zet de module Importeren aan om hem om te zetten naar een deck.',
    ),
    startsImport: false,
  );
}
