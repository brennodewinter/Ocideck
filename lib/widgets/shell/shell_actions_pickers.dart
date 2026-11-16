// Part of the app_shell library — see ../app_shell.dart.
// Split out for navigability; all imports live in the main library file.
part of '../app_shell.dart';

/// Open-pad voor web: de browser-picker levert de bestandsinhoud als bytes
/// (er bestaat geen pad), waarna het deck in-memory wordt geopend — een
/// `.ocideck`-pakket wordt daarbij in het geheugen uitgepakt. Opslaan van
/// zo'n tabblad wordt automatisch een download (geen [DeckState.filePath]).
Future<void> _openWithBytesPicker(BuildContext context, WidgetRef ref) async {
  final picked = await ref.read(fileServiceProvider).pickDeckFileBytes();
  if (picked == null || !context.mounted) return;
  if (p.extension(picked.name).toLowerCase() == '.pdf' ||
      isSupportedPdfEvidence(picked.bytes)) {
    await _openPdfBytes(context, picked.bytes, picked.name);
    return;
  }
  // Media vóór de deck-poort: de bytes zijn er al, de `mem:`-sleutel
  // wordt de sourcePath van de transcriptievoorbeschouwing (#2932).
  if (!context.mounted) return;
  if (await openMediaBytesIfMedia(context, picked.bytes, picked.name)) {
    return;
  }
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  // Geen extensie-check: de bytes-poort herkent pakketten aan hun zip-kop en
  // weigert al het andere met een gerichte melding via _reportOpenFailure.
  final openResult = await ref
      .read(tabsProvider.notifier)
      .openDeckFromBytes(picked.bytes, picked.name);
  // Zelfde laadwacht als het desktop-openpad (#1209) vóór de melding valt.
  final importModuleAvailable = await importModuleRevealedWhenReady(ref);
  if (!context.mounted) return;
  // Op web zijn de bytes al binnen: een presentatie of een kantoorbestand kan
  // direct de import in; de naam bepaalt welke importeur.
  _reportOpenFailure(
    messenger,
    l10n,
    openResult,
    reason: ref.read(openFailureProvider),
    sourceName: picked.name,
    importModuleAvailable: importModuleAvailable,
    onImport: () =>
        importNamedFile(context, ref, bytes: picked.bytes, name: picked.name),
    onOpenSettings: () => SettingsDialog.show(context),
  );
}

/// Scan a fixed set of well-known folders for Marp presentations and open the
/// chosen one. Complements [_openWithSearch], which scans a single folder.
Future<void> _scanLibrary(BuildContext context, WidgetRef ref) async {
  final path = await ScanLibraryDialog.show(
    context,
    fileService: ref.read(fileServiceProvider),
    recentFiles: [
      for (final f in ref.read(settingsProvider).recentFiles) f.path,
    ],
    homeDir: ref.read(settingsProvider).homeDirectory,
    showPreview: ref.read(settingsProvider).showOpenPreview,
  );
  if (path == null || !context.mounted) return;
  // Dezelfde classificatie als de kiezer: een mediabestand uit een
  // bibliotheekmap is media, geen mislukte tekstlezing (#2932).
  if (await openMediaPathIfMedia(context, path)) return;
  await ref.read(tabsProvider.notifier).openFileByPath(path);
}

/// Vraag een URL op, haal de presentatie (een .ocideck-pakket of een Marp-
/// markdownbestand) op en open hem. Toont een melding als ophalen mislukt.
/// Gedeeld door het hoofdmenu én het openscherm, zodat je ook bij het openen
/// online een presentatie kunt ophalen.
Future<void> _importFromUrl(BuildContext context, WidgetRef ref) async {
  final url = await _showUrlDialog(context);
  if (url == null || url.trim().isEmpty || !context.mounted) return;
  if (isWebPlatform) {
    // Web: de browser haalt het bestand op (CORS + CSP bewaken het verkeer)
    // en het deck wordt volledig in het geheugen geopend — het dart:io-
    // downloadpad hieronder bestaat op web niet.
    final result = await _importUrlWeb(context, ref, url);
    // Na een geslaagde open is de `?deck=`-deellink dé manier om de
    // presentatie door te sturen — bieden we meteen aan (#2826).
    if (result == OpenResult.opened && context.mounted) {
      final messenger = ScaffoldMessenger.of(context);
      final l10n = context.l10n;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.d('Geopend.')),
          action: SnackBarAction(
            label: l10n.d('Deellink kopiëren'),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: deckShareLink(Uri.base, url)),
              );
              if (context.mounted) {
                messenger.showSnackBar(
                  SnackBar(content: Text(l10n.d('Deellink gekopieerd.'))),
                );
              }
            },
          ),
        ),
      );
    }
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  ImportFailure? failure;
  try {
    failure = await ref
        .read(tabsProvider.notifier)
        .importFromUrl(url, homeDir: ref.read(settingsProvider).homeDirectory);
  } catch (e, s) {
    // Een platform- of IO-fout mag nooit als stilte eindigen: de gebruiker
    // heeft net een URL ingetikt en verwacht óf een tab óf een melding.
    logError('_importFromUrl: import failed', e, s);
    failure = ImportFailure.network;
  }
  if (failure != null && context.mounted) {
    showErrorSnackBar(messenger, l10n, importFailureMessage(l10n, failure));
  }
}

/// Open in OciDeck geplakte Markdowntekst (#2825) via exact dezelfde poort
/// als een geopend `.md`-bestand: de tekst wordt één keer UTF-8-gecodeerd en
/// [TabsNotifier.openDeckFromBytes] doet de rest — omvangsgrens,
/// veiligheidsscan met het importalarm, en routering naar presentatie of
/// document. De dialoog beheert de invoer en houdt hem vast als het openen
/// mislukt; deze functie levert alleen de melding die hij dan toont. De
/// inhoud gaat nergens heen — geen server, geen URL — en komt net als bij de
/// bestandsroute hooguit als telling in de logregels.
Future<void> _openPastedMarkdown(BuildContext context, WidgetRef ref) async {
  await PasteMarkdownDialog.show(
    context,
    onOpen: (text) async {
      final l10n = context.l10n;
      ref.read(openFailureProvider.notifier).state = null;
      final result = await ref
          .read(tabsProvider.notifier)
          .openDeckFromBytes(
            Uint8List.fromList(utf8.encode(text)),
            // Geen bestandsnaam om aan te houden: dit labelt alleen het
            // importalarm en de logregel.
            'geplakte-markdown.md',
          );
      if (result == OpenResult.opened) return null;
      if (result == OpenResult.blocked) {
        // Het importalarm toont zichzelf met de bevindingen; in de dialoog
        // volstaat de verwijzing — de details herhalen zou twee meldingen
        // over elkaar leggen.
        return l10n.d(
          'Deze tekst is niet geopend — zie de beveiligingsmelding.',
        );
      }
      return openFailureMessage(l10n, ref.read(openFailureProvider));
    },
  );
}
