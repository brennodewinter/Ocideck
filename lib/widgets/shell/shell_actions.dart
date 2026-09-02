// Part of the app_shell library — see ../app_shell.dart.
// Split out for navigability; all imports live in the main library file.
part of '../app_shell.dart';

/// Surface a failed open as a snackbar. `blocked` shows the security alarm
/// elsewhere and `opened` needs nothing, so both are silent here.
///
/// [reason] komt uit `openFailureProvider` en is er alleen wanneer het openpad
/// de oorzaak wérkelijk vaststelde. Is hij er niet, dan blijft het bij de
/// algemene melding — een reden verzinnen bij een onbekende oorzaak stuurt de
/// gebruiker de verkeerde kant op, en dat is erger dan vaag zijn.
void _reportOpenFailure(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  OpenResult result, {
  OpenFailure? reason,
  String? sourceName,
  bool importModuleAvailable = false,
  VoidCallback? onImport,
  VoidCallback? onOpenSettings,
}) {
  // Koos de gebruiker via "Openen" eigenlijk een presentatie, dan is import de
  // bedoeling: een melding mét uitweg, niet doodlopen op "OciDeck opent Markdown".
  if (sourceName != null &&
      (result == OpenResult.unreadable ||
          result == OpenResult.notAPresentation)) {
    final bar = presentationOpenRescueSnackBar(
      l10n,
      sourceName,
      importModuleAvailable: importModuleAvailable,
      onImport: onImport ?? () {},
      onOpenSettings: onOpenSettings ?? () {},
    );
    if (bar != null) {
      messenger.showSnackBar(bar);
      return;
    }
  }
  final message = switch (result) {
    OpenResult.notAPresentation => l10n.d(
      'Dit is geen Marp/OciDeck-presentatie.',
    ),
    OpenResult.unreadable => _unreadableMessage(l10n, reason),
    OpenResult.opened ||
    OpenResult.blocked ||
    OpenResult.passwordCancelled => null,
  };
  if (message != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

extension _DropActions on _AppShellState {
  /// Drag-drop op web: geen pad, alleen inhoud. `.md`/`.ocideck` opent in-memory
  /// (zelfde security-gate), afbeeldingen gaan de WebAssetStore in, een
  /// presentatie de import — net als op desktop; overige typen worden genegeerd.
  Future<void> _onWebFilesDropped(List<DropItem> files) async {
    final tabs = ref.read(tabsProvider.notifier);
    final images = <String>[];
    final presentations = <PickedPresentation>[];
    for (final file in files) {
      final ext = p.extension(file.name.toLowerCase());
      if (ext == '.md' || ext == '.ocideck' || ext == '.zip') {
        final bytes = await file.readAsBytes();
        final result = await tabs.openDeckFromBytes(bytes, file.name);
        if (mounted) {
          _reportOpenFailure(
            ScaffoldMessenger.of(context),
            context.l10n,
            result,
            reason: ref.read(openFailureProvider),
          );
        }
      } else if (isImportablePresentationName(file.name)) {
        presentations.add((bytes: await file.readAsBytes(), name: file.name));
      } else if (_AppShellState._imageExtensions.contains(ext)) {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty ||
            bytes.length > ImageService.maxImageBytes ||
            !ImageService.looksLikeImage(bytes)) {
          logWarning(
            'AppShell._onWebFilesDropped: afbeelding geweigerd '
            '(te groot of geen afbeelding)',
            file.name,
          );
          continue;
        }
        final outcome = ImageService.storeWebImage(bytes, name: file.name);
        final path = outcome.path;
        if (path != null) {
          images.add(path);
        } else if (mounted &&
            outcome.failure == ImageImportFailure.memoryBudgetExceeded) {
          showErrorSnackBar(
            ScaffoldMessenger.of(context),
            context.l10n,
            webAssetBudgetMessage(context.l10n),
          );
        }
      }
    }
    if (images.isNotEmpty) _addImagesToActiveDeck(images);
    if (presentations.isNotEmpty && mounted) {
      await importDroppedPresentations(context, ref, presentations);
    }
  }
}

/// Wat er misging, zo precies als het openpad het wist.
///
/// "Kon dit bestand niet openen." stond hier voor vier verschillende dingen,
/// terwijl `FileService.openDeckDetailed` het antwoord al had. Voor een product
/// dat om Markdown draait is dat te mager: de gebruiker weet dan niet of hij het
/// verkeerde bestand koos, of dat er iets stuk is, of dat hij iets kán doen.
String _unreadableMessage(
  AppLocalizations l10n,
  OpenFailure? reason,
) => switch (reason) {
  OpenFailure.notFound => l10n.d('Dit bestand bestaat niet meer op deze plek.'),
  OpenFailure.tooLarge => l10n.d('Dit bestand is te groot om te openen.'),
  OpenFailure.memoryBudgetExceeded => webAssetBudgetMessage(l10n),
  OpenFailure.corrupt => l10n.d(
    'Deze presentatie is beschadigd of half opgeslagen.',
  ),
  OpenFailure.unreadable => l10n.d(
    'Dit bestand is geen leesbare tekst. OciDeck opent Markdown.',
  ),
  // `unsafe` en `notPresentation` komen hier niet langs: die hebben hun
  // eigen afhandeling (het veiligheidsalarm en OpenResult.notAPresentation).
  // Null is het eerlijke geval — een afgebroken open, een tabblad dat
  // verdween — en houdt de algemene zin.
  OpenFailure.unsafe ||
  OpenFailure.notPresentation ||
  null => l10n.d('Kon dit bestand niet openen.'),
};

/// Open een presentatie of document via de zoek-/kies-dialoog: de ingestelde
/// bibliotheken worden doorzocht, de gebruiker kiest een bestand (of bladert
/// naar één buiten de bibliotheken), en het opent in een tabblad. Op web is er
/// geen bestandssysteem om te doorzoeken; daar levert de browser-picker bytes.
Future<void> _openWithSearch(BuildContext context, WidgetRef ref) async {
  // Op web is er geen bestandssysteem om te doorzoeken; alle open-ingangen
  // (welkomstscherm, menu, Ctrl/Cmd+O) lopen daar via de browser-picker.
  if (isWebPlatform) {
    return _openWithBytesPicker(context, ref);
  }
  final settings = ref.read(settingsProvider);
  final result = await OpenPresentationDialog.show(
    context,
    fileService: ref.read(fileServiceProvider),
    libraries: settings.libraries,
    showPreview: settings.showOpenPreview,
  );
  if (result == null || !context.mounted) return;
  // Bladeren… sluit het dialoog eerst; daarna pas de native kiezer — anders
  // blijft .md grijs onder een geneste Flutter-modal (macOS).
  final String path;
  final int? selectIndex;
  if (result.browseRequested) {
    final picked = await ref
        .read(fileServiceProvider)
        .pickMarkdownFile(
          initialDirectory: settings.libraries.isEmpty
              ? null
              : settings.libraries.first.path,
        );
    if (picked == null || !context.mounted) return;
    path = picked;
    selectIndex = null;
  } else {
    final chosen = result.path;
    if (chosen == null) return;
    path = chosen;
    selectIndex = result.slideIndex;
  }
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final openResult = await ref
      .read(tabsProvider.notifier)
      .openFileByPath(path, selectIndex: selectIndex);
  // Wacht op de geladen module-stand vóór de melding gekozen wordt: vlak na de
  // start leest de reveal anders nog de ladende default (#1209).
  final importModuleAvailable = await importModuleRevealedWhenReady(ref);
  if (!context.mounted) return;
  // openFileByPath routet een leesbaar niet-marp `.md` naar een documenttabblad.
  // Alleen échte weigeringen (onleesbaar, of een Office-bestand zonder marp)
  // komen hier als snackbar — met de importroute als uitweg waar die past.
  _reportOpenFailure(
    messenger,
    l10n,
    openResult,
    reason: ref.read(openFailureProvider),
    sourceName: path,
    importModuleAvailable: importModuleAvailable,
    // Pad al bekend: importeer zonder de bestandskiezer opnieuw te openen.
    onImport: () async {
      final bytes = await File(path).readAsBytes();
      if (!context.mounted) return;
      await importPresentation(
        context,
        ref,
        fileOverride: (bytes: bytes, name: p.basename(path)),
      );
    },
    onOpenSettings: () => SettingsDialog.show(context),
  );
}

/// Open-pad voor web: de browser-picker levert de bestandsinhoud als bytes
/// (er bestaat geen pad), waarna het deck in-memory wordt geopend — een
/// `.ocideck`-pakket wordt daarbij in het geheugen uitgepakt. Opslaan van
/// zo'n tabblad wordt automatisch een download (geen [DeckState.filePath]).
Future<void> _openWithBytesPicker(BuildContext context, WidgetRef ref) async {
  final picked = await ref.read(fileServiceProvider).pickDeckFileBytes();
  if (picked == null || !context.mounted) return;
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
  // Op web zijn de bytes al binnen: een presentatie kan direct de import in.
  _reportOpenFailure(
    messenger,
    l10n,
    openResult,
    reason: ref.read(openFailureProvider),
    sourceName: picked.name,
    importModuleAvailable: importModuleAvailable,
    onImport: () => importPresentation(
      context,
      ref,
      fileOverride: (bytes: picked.bytes, name: picked.name),
    ),
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
  if (path == null) return;
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
    return _importUrlWeb(context, ref, url);
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

/// Web-kern van de URL-import: ophalen (met hulppunt-terugval), dezelfde
/// security-gate, en de juiste melding. Gedeeld door de importdialoog en de
/// `?deck=`-deeplink waarmee een link OciDeck én een presentatie tegelijk
/// opent.
Future<void> _importUrlWeb(
  BuildContext context,
  WidgetRef ref,
  String url,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  OpenResult result;
  ImportFailure? fetchFailure;
  try {
    ref.read(openFailureProvider.notifier).state = null;
    final outcome = await ref.read(tabsProvider.notifier).importFromUrlWeb(url);
    result = outcome.result;
    fetchFailure = outcome.failure;
  } catch (e, s) {
    logError('_importUrlWeb: import failed', e, s);
    result = OpenResult.unreadable;
    fetchFailure = null;
  }
  if (result == OpenResult.notAPresentation) {
    _reportOpenFailure(messenger, l10n, result);
    return;
  }
  if (result == OpenResult.opened ||
      result == OpenResult.blocked ||
      result == OpenResult.passwordCancelled) {
    return;
  }
  // Een concrete ophaalreden (te groot, 404, geen http(s)-link, geweigerde
  // host, omleiding) is specifieker dan CORS: toon díe. Alleen de ondoorzichtige
  // browserweigering ([ImportFailure.network]) valt door naar de CORS-uitleg
  // hieronder, want dán klopt hij.
  if (fetchFailure != null && fetchFailure != ImportFailure.network) {
    showErrorSnackBar(
      messenger,
      l10n,
      importFailureMessage(l10n, fetchFailure),
    );
    return;
  }
  // Ophalen slaagde maar het openen niet (beschadigd deck, vol mediabudget):
  // openDeckFromBytes legde de reden vast, en die is specifieker dan CORS.
  final reason = ref.read(openFailureProvider);
  if (reason != null) {
    _reportOpenFailure(messenger, l10n, result, reason: reason);
    return;
  }
  // Op web is de meest voorkomende oorzaak geen tikfout maar CORS: de
  // browser mag alleen lezen van servers die dat expliciet toestaan.
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        '${l10n.d('Kon van deze URL geen presentatie ophalen.')}\n'
        '${l10n.d('Let op: de webversie kan alleen ophalen van servers die dit toestaan (CORS).')}',
      ),
    ),
  );
}

/// Kies een deck uit de git-repository, haal het op, door de security-gate en
/// open het in een tab. Anders dan Nextcloud werkt dit óók op web: het
/// forge-plane is gewoon https+JSON dat de browser-sandbox al inperkt, terwijl
/// de WebDAV-client op dart:io-pinning leunt die daar niet bestaat (§4.4).
///
/// Met [deckDir] slaat het de keuzedialoog over en opent het dat deck direct —
/// zo komt een zoekresultaat langs precies dezelfde gate en hetzelfde
/// native/REST-onderscheid als de bladeraar, in plaats van via een tweede
/// openpad dat uit de pas gaat lopen.
Future<void> _openFromGit(
  BuildContext context,
  WidgetRef ref, {
  String? deckDir,
  GitConnection? connection,
}) async {
  final chosen0 = connection ?? await _pickGitConnection(context, ref);
  if (chosen0 == null || !context.mounted) return;
  final forge = await ref.read(gitForgeProvider(chosen0.id).future);
  if (!context.mounted) return;
  if (forge == null) {
    _gitNotConfigured(context);
    return;
  }
  final chosen =
      deckDir ?? await GitBrowserDialog.show(context, connectionId: chosen0.id);
  if (chosen == null || !context.mounted) return;

  final config = chosen0.repo;
  // Native git als het er is: openen uit de lokale clone, met de clone-HEAD als
  // basis. Anders het REST-pad.
  final native = await ref.read(nativeGitMirrorProvider(chosen0.id).future);
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    final notifier = ref.read(tabsProvider.notifier);
    ref.read(openFailureProvider.notifier).state = null;
    final result = native != null
        ? await notifier.openDeckFromGitNative(
            native,
            forge,
            config: config,
            deckDir: chosen,
            branch: config.defaultBranch,
            connectionId: chosen0.id,
          )
        : await notifier.openDeckFromGit(
            forge,
            config: config,
            deckDir: chosen,
            branch: config.defaultBranch,
            connectionId: chosen0.id,
          );
    _reportOpenFailure(
      messenger,
      l10n,
      result,
      reason: ref.read(openFailureProvider),
    );
  } on GitForgeException catch (e) {
    // De uitzondering draagt al een uitlegbare tekst; die is voor de gebruiker
    // bedoeld, dus toon hem in plaats van een eigen samenvatting.
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } on GitCliException catch (e) {
    // Het native plane faalt met git's stderr in een GitCliException. Zonder
    // deze tak verdween een clone-fout (verkeerd token, repo weg, foute of lege
    // branch) stil in runZonedGuarded en opende er niets. Classificeer de stderr
    // naar dezelfde begrijpelijke melding als de REST-weg.
    logWarning('shell: git clone/openen mislukt', e);
    messenger.showSnackBar(SnackBar(content: Text(userFacingError(l10n, e))));
  } catch (e, s) {
    // Vangnet: een niet-git-fout (een schrijffout in de clone, een te groot
    // pakket) mag evenmin stil eindigen — dan opent er niets zonder reden.
    logError('shell: git openen mislukt', e, s);
    messenger.showSnackBar(SnackBar(content: Text(userFacingError(l10n, e))));
  }
}

Future<_RemoteConflict?> _showRemoteConflictDialog(BuildContext context) {
  final l10n = context.l10n;
  return showDialog<_RemoteConflict>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.d('Iemand anders heeft dit bestand gewijzigd')),
      content: Text(
        l10n.d(
          'Sinds je dit deck opende is de versie op de server veranderd. Overschrijven maakt het werk van de ander ongedaan.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.t('cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, _RemoteConflict.overwrite),
          child: Text(l10n.d('Overschrijven')),
        ),
        // Als voorkeursknop rechts: hij behoudt beide versies, en dat is wat
        // je wilt aanraden aan iemand die dit scherm onverwacht krijgt.
        FilledButton(
          onPressed: () => Navigator.pop(ctx, _RemoteConflict.saveAs),
          child: Text(l10n.d('Opslaan als')),
        ),
      ],
    ),
  );
}

/// Maak een veilige bestandsnaam (zonder extensie) uit een deck-titel.
/// Gedeelde sanitizer uit `lib/utils/safe_filename.dart`.
String _safeRemoteName(String title) =>
    sanitizeFilename(title, fallback: 'presentatie');

/// Keuze uit het opslaan-dialoog: formaat plus doelpad (zonder extensie,
/// relatief aan de wortelmap).
typedef _RemoteSaveChoice = ({DeckSaveFormat format, String base});

Future<_RemoteSaveChoice?> _showRemoteSaveDialog(
  BuildContext context, {
  required String defaultBase,
  required String title,
}) {
  return showDialog<_RemoteSaveChoice>(
    context: context,
    builder: (_) => _RemoteSaveDialog(defaultBase: defaultBase, title: title),
  );
}

class _RemoteSaveDialog extends StatefulWidget {
  final String defaultBase;

  /// De kop verschilt per bron ("naar WebDAV" / "naar S3"); de rest van het
  /// dialoog is dezelfde vraag.
  final String title;
  const _RemoteSaveDialog({required this.defaultBase, required this.title});

  @override
  State<_RemoteSaveDialog> createState() => _RemoteSaveDialogState();
}

class _RemoteSaveDialogState extends State<_RemoteSaveDialog> {
  late final TextEditingController _path = TextEditingController(
    text: widget.defaultBase,
  );
  DeckSaveFormat _format = DeckSaveFormat.ocideck;

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _path,
              decoration: InputDecoration(
                labelText: l10n.d('Doelpad (zonder extensie)'),
                hintText: l10n.d('map/presentatie'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            RadioGroup<DeckSaveFormat>(
              groupValue: _format,
              onChanged: (v) => setState(() => _format = v!),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<DeckSaveFormat>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: DeckSaveFormat.ocideck,
                    title: Text(
                      l10n.d('Als .ocideck-pakket (één bestand, met assets)'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  RadioListTile<DeckSaveFormat>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: DeckSaveFormat.flat,
                    title: Text(
                      l10n.d('Als losse .md plus afbeeldingen'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.t('cancel')),
        ),
        ElevatedButton.icon(
          onPressed: () {
            final base = _path.text.trim().replaceAll(RegExp(r'^/+'), '');
            if (base.isEmpty) return;
            Navigator.pop(context, (format: _format, base: base));
          },
          icon: const Icon(Icons.cloud_upload_outlined, size: 16),
          label: Text(l10n.d('Opslaan')),
        ),
      ],
    );
  }
}

/// Vraag een URL op om een presentatie (pakket of markdown) op te halen.
Future<String?> _showUrlDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _UrlImportDialog(),
  );
}

class _UrlImportDialog extends StatefulWidget {
  const _UrlImportDialog();

  @override
  State<_UrlImportDialog> createState() => _UrlImportDialogState();
}

class _UrlImportDialogState extends State<_UrlImportDialog> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Herbouw bij elke wijziging zodat de Ophalen-knop live aan/uit gaat.
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Alleen een http(s)-URL met host is op te halen; alles daarbuiten laat
  /// de knop uit staan i.p.v. stil te falen na het klikken.
  bool get _isFetchable {
    final uri = Uri.tryParse(_controller.text.trim());
    if (uri == null || uri.host.isEmpty) return false;
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Importeren via URL')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Plak de link naar een .ocideck-pakket of een Marp-markdownbestand.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate500),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: l10n.d('https://...'),
                prefixIcon: const Icon(Icons.link, size: 18),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (v) {
                if (_isFetchable) Navigator.pop(context, v);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.t('cancel')),
        ),
        ElevatedButton.icon(
          onPressed: _isFetchable
              ? () => Navigator.pop(context, _controller.text)
              : null,
          icon: const Icon(Icons.download, size: 16),
          label: Text(l10n.d('Ophalen')),
        ),
      ],
    );
  }
}

List<String> _imageSearchPaths(String? projectPath, List<String> libraryPaths) {
  return deckImageSearchPaths(projectPath, libraryPaths);
}

String? _resolveImagePath(String path, String? projectPath) {
  return resolveEditorAssetPath(path, projectPath);
}

List<String> _imageUsages(WidgetRef ref, String absolutePath) {
  final target = p.normalize(absolutePath);
  final usages = <String>[];
  for (final tab in ref.read(tabsProvider).tabs) {
    final deck = tab.deckNotifier.currentState.deck;
    if (deck == null) continue;
    // De insluitingswacht doet hier het oplossen: een pad dat buiten de
    // presentatie zou wijzen levert geen treffer op in plaats van er een te
    // verzinnen.
    String? resolve(String candidate) {
      final resolved = resolveSlideAssetPath(candidate, deck.projectPath);
      return resolved == null ? null : p.normalize(resolved);
    }

    for (final i in slideIndexesUsingImage(deck, target, resolve)) {
      usages.add('${tab.label} · slide ${i + 1}');
    }
  }
  return usages;
}

/// Wijs in alle open decks elke slideverwijzing naar [fromAbsolute] om naar
/// [toAbsolute]. Gebruikt door de afbeeldingenbibliotheek wanneer een md5-
/// duplicaat wordt opgeruimd, zodat slides het behouden bestand blijven tonen.
Future<void> _replaceImageUsages(
  WidgetRef ref,
  String fromAbsolute,
  String toAbsolute,
) async {
  final target = p.normalize(fromAbsolute);
  for (final tab in ref.read(tabsProvider).tabs) {
    final notifier = tab.deckNotifier;
    final deck = notifier.currentState.deck;
    if (deck == null) continue;
    final projectPath = deck.projectPath ?? '';

    String? resolve(String candidate) {
      final resolved = resolveSlideAssetPath(candidate, deck.projectPath);
      return resolved == null ? null : p.normalize(resolved);
    }

    // Blijf relatief opslaan als de slide dat al deed en het nieuwe pad
    // binnen het project ligt; anders absoluut.
    String replacement(String candidate) {
      if (p.isAbsolute(candidate) || projectPath.isEmpty) return toAbsolute;
      return p.isWithin(projectPath, toAbsolute)
          ? p.relative(toAbsolute, from: projectPath)
          : toAbsolute;
    }

    for (var i = 0; i < deck.slides.length; i++) {
      final slide = deck.slides[i];
      final updated = slideWithImageReplaced(
        slide,
        target,
        resolve,
        replacement,
      );
      if (!identical(updated, slide)) notifier.updateSlide(i, updated);
    }
  }
}

List<Slide> _slidesForPresentationOrExport(
  Deck deck, {
  bool includeDetail = true,
}) {
  // Welke slides het publiek bereiken staat in één predicaat; zie
  // [slideReachesAudience]. Presenteren neemt de verdieping altijd mee — de
  // beknopte versie is een exportkeuze, niet iets wat je halverwege een
  // presentatie wilt ontdekken.
  final slides = deck.slides
      .where(
        (s) => slideReachesAudience(
          s,
          presentationTlp: deck.tlp,
          includeDetail: includeDetail,
        ),
      )
      .toList();
  final closingMarkdown = deck.themeProfile.closingSlideMarkdown.trim();
  if (deck.themeProfile.closingSlideEnabled && closingMarkdown.isNotEmpty) {
    slides.add(
      Slide.create(
        SlideType.freeMarkdown,
      ).copyWith(customMarkdown: closingMarkdown),
    );
  }
  return slides;
}

/// Waarom er geen enkele dia overblijft, in de woorden van de échte oorzaak.
///
/// Er stond hier één zin — "Alle slides zijn overgeslagen" — en die wees naar de
/// verkeerde knop zodra de oorzaak TLP was: een dia met een strengere
/// classificatie dan de presentatie valt óók weg, maar heeft niets met overslaan
/// te maken en is met "Alles tonen" niet terug te krijgen. De twee blijven hier
/// dus uit elkaar, ook wanneer ze samen optreden.
String emptyAudienceReason(
  AppLocalizations l10n,
  Deck deck, {
  required bool forExport,
}) {
  final skipped = deck.slides.any((s) => s.skipped);
  final withheld = deck.slides.any((s) => slideWithheldByTlp(s, deck.tlp));
  if (withheld && skipped) {
    return forExport
        ? l10n.d(
            'Alle slides zijn overgeslagen of achtergehouden door hun TLP-classificatie — niets om te exporteren.',
          )
        : l10n.d(
            'Alle slides zijn overgeslagen of achtergehouden door hun TLP-classificatie — niets om te tonen.',
          );
  }
  if (withheld) {
    return forExport
        ? l10n.d(
            'Alle slides zijn achtergehouden door hun TLP-classificatie — niets om te exporteren.',
          )
        : l10n.d(
            'Alle slides zijn achtergehouden door hun TLP-classificatie — niets om te tonen.',
          );
  }
  return forExport
      ? l10n.d('Alle slides zijn overgeslagen — niets om te exporteren.')
      : l10n.d('Alle slides zijn overgeslagen — niets om te tonen.');
}

/// Toont de "niet-opgeslagen wijzigingen"-dialoog en geeft de keuze terug.
/// Top-level zodat zowel de tabbalk als het 'alleen afspelen'-scherm hetzelfde
/// dialoog gebruiken.
Future<_CloseChoice> _confirmSaveBeforeCloseDialog(
  BuildContext context,
  String message,
) async {
  if (!context.mounted) return _CloseChoice.cancel;
  return await showDialog<_CloseChoice>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          final l10n = ctx.l10n;
          return AlertDialog(
            title: Text(l10n.d('Niet-opgeslagen wijzigingen')),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, _CloseChoice.cancel),
                child: Text(l10n.t('cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, _CloseChoice.discard),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(ctx).colorScheme.error,
                ),
                child: Text(l10n.d('Niet opslaan')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, _CloseChoice.save),
                child: Text(l10n.d('Opslaan en sluiten')),
              ),
            ],
          );
        },
      ) ??
      _CloseChoice.cancel;
}

/// Sluit het tabblad op [index], met de "niet-opgeslagen wijzigingen"-check.
/// Gedeeld door de tabbalk (kruisje/middenklik) en het 'alleen afspelen'-scherm
/// zodat sluiten overal dezelfde afhandeling volgt.
Future<void> requestCloseTab(
  BuildContext context,
  WidgetRef ref,
  int index,
) async {
  final tabs = ref.read(tabsProvider).tabs;
  if (index < 0 || index >= tabs.length) return;
  final tab = tabs[index];
  if (tab.isDirty) {
    final l10n = context.l10n;
    // De melding noemt de soort: een document is geen presentatie. Vroeger
    // stond hier voor elk tabblad de presentatie-tekst, en voor een vuil
    // documenttabblad ging het opslaan via `tab.deckNotifier` — dat gooit
    // voor een document (StateError), dus het tabblad sloot nooit (#1614).
    final message = tab.kind.isDocument
        ? l10n.d(
            'Dit document heeft niet-opgeslagen wijzigingen. Sla het document op voordat het tabblad sluit.',
          )
        : l10n.d(
            'Deze presentatie heeft niet-opgeslagen wijzigingen. Sla de presentatie op voordat het tabblad sluit.',
          );
    final choice = await _confirmSaveBeforeCloseDialog(context, message);
    if (!context.mounted) return;
    switch (choice) {
      case _CloseChoice.cancel:
        return;
      case _CloseChoice.discard:
        // Wijzigingen verwerpen: closeTab() ruimt ook het herstelbestand op.
        break;
      case _CloseChoice.save:
        // saveTabWithDestination routeert op soort: een document byte-getrouw
        // via zijn eigen pad, een presentatie via de deck-route. Vroeger ging
        // dit via tab.deckNotifier, dat voor een documenttabblad gooit.
        final saved = await saveTabWithDestination(context, ref, tab);
        if (!saved) return;
    }
  }
  ref.read(tabsProvider.notifier).closeTab(index);
}
