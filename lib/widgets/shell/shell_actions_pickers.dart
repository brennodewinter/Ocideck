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
