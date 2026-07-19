// Part of the app_shell library — see ../app_shell.dart.
// Split out for navigability; all imports live in the main library file.
part of '../app_shell.dart';

/// Surface a failed open as a snackbar. `blocked` shows the security alarm
/// elsewhere and `opened` needs nothing, so both are silent here.
void _reportOpenFailure(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  OpenResult result,
) {
  final message = switch (result) {
    OpenResult.notAPresentation => l10n.d(
      'Dit is geen Marp/OciDeck-presentatie.',
    ),
    OpenResult.unreadable => l10n.d('Kon dit bestand niet openen.'),
    OpenResult.opened ||
    OpenResult.blocked ||
    OpenResult.passwordCancelled => null,
  };
  if (message != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Exporteer het huidige deck als zelfstandig `.ocideck`-pakket. Toont eerst de
/// [PackageEncryptDialog] zodat de gebruiker het pakket optioneel met een
/// wachtwoord (AES-256) kan beschermen; annuleren daar breekt de export af. Op
/// web wordt het pakket in het geheugen gebouwd en als download aangeboden.
Future<void> _exportPackage(BuildContext context, WidgetRef ref) async {
  final deck = ref.read(deckProvider).deck!;
  final choice = await PackageEncryptDialog.show(context);
  if (choice == null || !context.mounted) return;
  final password = choice.encrypt ? choice.password : null;
  final l10n = context.l10n;
  final fileService = ref.read(fileServiceProvider);
  try {
    final String dest;
    if (isWebPlatform) {
      dest = await fileService.downloadPackage(deck, password: password);
    } else {
      final picked = await fileService.pickPackageDestination(deck);
      if (picked == null) return;
      await fileService.exportPackage(deck, picked, password: password);
      dest = picked;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${l10n.d('Pakket geëxporteerd naar:')}\n$dest')),
    );
  } catch (e) {
    logError('AppShell: pakketexport mislukt', e);
    if (!context.mounted) return;
    showErrorSnackBar(
      ScaffoldMessenger.of(context),
      l10n,
      '${l10n.d('Export mislukt:')} ${userFacingError(l10n, e)}',
    );
  }
}

/// Exporteer een one-click auditdossier (MIAUW §10.11): het verzegelde rapport
/// (`.md` + assets + bewijs) plus een `AUDIT_DOSSIER.md`-index met de zegel-,
/// samenvattings-, compliance- en bewijs-hashgegevens, optioneel met AES-256.
/// Vereist een gefinaliseerd, verzegeld deck; leest de bewijs-afbeeldingen van
/// schijf om de hashtabel op te bouwen (onleesbare worden overgeslagen).
Future<void> _exportAuditDossier(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final deck = ref.read(deckProvider).deck!;
  if (!(deck.finalized && deck.sealHash.trim().isNotEmpty)) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.d('Finaliseer en verzegel het rapport eerst.')),
      ),
    );
    return;
  }
  final imageService = ImageService();
  final hashes = <String, EvidenceHashes>{};
  for (final slide in deck.slides) {
    if (slide.findingRole != FindingRole.evidence || slide.imagePath.isEmpty) {
      continue;
    }
    final bytes = await imageService.readSlideImageBytes(
      slide.imagePath,
      projectPath: deck.projectPath,
    );
    if (bytes != null) hashes[slide.imagePath] = computeEvidenceHashes(bytes);
  }
  if (!context.mounted) return;
  final choice = await PackageEncryptDialog.show(context);
  if (choice == null || !context.mounted) return;
  final password = choice.encrypt ? choice.password : null;
  final index = buildAuditDossier(deck, evidenceHashes: hashes);
  final fileService = ref.read(fileServiceProvider);
  try {
    final String dest;
    if (isWebPlatform) {
      dest = await fileService.downloadDossier(
        deck,
        dossierIndex: index,
        password: password,
      );
    } else {
      final picked = await fileService.pickDossierDestination(deck);
      if (picked == null) return;
      await fileService.exportDossier(
        deck,
        picked,
        dossierIndex: index,
        password: password,
      );
      dest = picked;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${l10n.d('Auditdossier geëxporteerd naar:')}\n$dest'),
      ),
    );
  } catch (e) {
    logError('AppShell: auditdossier-export mislukt', e);
    if (!context.mounted) return;
    showErrorSnackBar(
      ScaffoldMessenger.of(context),
      l10n,
      '${l10n.d('Export mislukt:')} ${userFacingError(l10n, e)}',
    );
  }
}

/// Open the search-based presentation picker and load the chosen file
/// (optionally jumping to a matched slide). Scans every configured library.
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
  );
  if (result == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final openResult = await ref
      .read(tabsProvider.notifier)
      .openFileByPath(result.path, selectIndex: result.slideIndex);
  // A loose file browsed from disk that isn't a presentation (or is otherwise
  // unreadable) is refused — tell the user instead of doing nothing silently.
  _reportOpenFailure(messenger, l10n, openResult);
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
  _reportOpenFailure(messenger, l10n, openResult);
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
  try {
    result = await ref.read(tabsProvider.notifier).importFromUrlWeb(url);
  } catch (e, s) {
    logError('_importUrlWeb: import failed', e, s);
    result = OpenResult.unreadable;
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
}) async {
  final forge = await ref.read(gitForgeProvider.future);
  if (!context.mounted) return;
  if (forge == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.d(
            'Stel eerst een git-repository in bij Instellingen → Git-repository.',
          ),
        ),
      ),
    );
    return;
  }
  final chosen = deckDir ?? await GitBrowserDialog.show(context);
  if (chosen == null || !context.mounted) return;

  final config = ref.read(settingsProvider).gitRepo;
  if (config == null) return;
  // Native git als het er is: openen uit de lokale clone, met de clone-HEAD als
  // basis. Anders het REST-pad.
  final native = await ref.read(nativeGitMirrorProvider.future);
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    final notifier = ref.read(tabsProvider.notifier);
    final result = native != null
        ? await notifier.openDeckFromGitNative(
            native,
            forge,
            config: config,
            deckDir: chosen,
            branch: config.defaultBranch,
          )
        : await notifier.openDeckFromGit(
            forge,
            config: config,
            deckDir: chosen,
            branch: config.defaultBranch,
          );
    _reportOpenFailure(messenger, l10n, result);
  } on GitForgeException catch (e) {
    // De uitzondering draagt al een uitlegbare tekst; die is voor de gebruiker
    // bedoeld, dus toon hem in plaats van een eigen samenvatting.
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// Blader door de Nextcloud/WebDAV-bron, download het gekozen deck, haal het
/// door de security-gate en open het in een tab. Toont waar nodig een melding.
Future<void> _openFromNextcloud(BuildContext context, WidgetRef ref) async {
  final service = await ref.read(webdavServiceProvider.future);
  if (!context.mounted) return;
  if (service == null) {
    _webdavNotConfigured(context);
    return;
  }
  final entry = await WebdavBrowserDialog.show(context);
  if (entry == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    final result = await ref
        .read(tabsProvider.notifier)
        .openFromWebdav(
          service,
          entry,
          homeDir: ref.read(settingsProvider).homeDirectory,
        );
    _reportOpenFailure(messenger, l10n, result);
    // OpenResult.blocked toont al het veiligheidsalarm via de shell.
  } on WebdavException catch (e) {
    logWarning('shell: WebDAV-download mislukt', e);
    showErrorSnackBar(
      messenger,
      l10n,
      '${l10n.d('Downloaden mislukt:')} ${webdavErrorMessage(l10n, e)}',
    );
  }
}

/// Schrijf het deck van het huidige tabblad terug naar Nextcloud. Vraagt het
/// formaat (pakket of platte bestanden) en het doelpad, en uploadt dan.
Future<void> _saveToNextcloud(BuildContext context, WidgetRef ref) async {
  final tab = ref.read(tabsProvider).current;
  final deck = tab?.deckNotifier.currentState.deck;
  if (tab == null || deck == null) return;
  final service = await ref.read(webdavServiceProvider.future);
  if (!context.mounted) return;
  if (service == null) {
    _webdavNotConfigured(context);
    return;
  }
  // Standaardpad: hergebruik de herkomst als die van dezelfde server komt,
  // anders een nette bestandsnaam uit de deck-titel in de wortelmap.
  final origin = tab.webdavOrigin;
  final reuse = origin != null && origin.matchesServer(service.server);
  final defaultBase = reuse
      ? origin.remotePath.replaceAll(RegExp(r'\.(ocideck|zip|md)$'), '')
      : _safeRemoteName(deck.title);
  var choice = await _showWebdavSaveDialog(context, defaultBase: defaultBase);
  if (choice == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  // Blijft doorlopen zolang de gebruiker na een botsing een andere weg kiest:
  // onder een nieuwe naam opslaan, of alsnog overschrijven.
  var overwrite = false;
  while (true) {
    final ext = choice!.format == WebdavSaveFormat.ocideck ? '.ocideck' : '.md';
    final targetPath = '${choice.base}$ext';
    try {
      await ref
          .read(tabsProvider.notifier)
          .saveToWebdav(
            tab,
            service,
            format: choice.format,
            targetPath: targetPath,
            overwrite: overwrite,
          );
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('${l10n.d('Opgeslagen op WebDAV:')} /$targetPath'),
        ),
      );
      return;
    } on WebdavConflictException catch (e) {
      logWarning('shell: WebDAV-opslaan botste met een nieuwere versie', e);
      if (!context.mounted) return;
      final resolution = await _showWebdavConflictDialog(context);
      if (resolution == null || !context.mounted) return;
      switch (resolution) {
        case _WebdavConflict.overwrite:
          overwrite = true;
        case _WebdavConflict.saveAs:
          final next = await _showWebdavSaveDialog(
            context,
            defaultBase: choice.base,
          );
          if (next == null || !context.mounted) return;
          choice = next;
          // Een ander doelpad wordt niet bewaakt (we haalden het nooit op),
          // maar een ongewijzigd pad moet de guard hóuden.
          overwrite = false;
      }
    } on WebdavException catch (e) {
      logWarning('shell: WebDAV-opslaan mislukt', e);
      showErrorSnackBar(
        messenger,
        l10n,
        '${l10n.d('Opslaan mislukt:')} ${webdavErrorMessage(l10n, e)}',
      );
      return;
    }
  }
}

/// Wat de gebruiker doet als het bestand op de server inmiddels van iemand
/// anders is. Bewust geen samenvoegkeuze zoals bij git: die leunt erop dat de
/// basisversie nog opvraagbaar is, en bij WebDAV is die weg zodra de ander
/// heeft geüpload.
enum _WebdavConflict { saveAs, overwrite }

Future<_WebdavConflict?> _showWebdavConflictDialog(BuildContext context) {
  final l10n = context.l10n;
  return showDialog<_WebdavConflict>(
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
          onPressed: () => Navigator.pop(ctx, _WebdavConflict.overwrite),
          child: Text(l10n.d('Overschrijven')),
        ),
        // Als voorkeursknop rechts: hij behoudt beide versies, en dat is wat
        // je wilt aanraden aan iemand die dit scherm onverwacht krijgt.
        FilledButton(
          onPressed: () => Navigator.pop(ctx, _WebdavConflict.saveAs),
          child: Text(l10n.d('Opslaan als')),
        ),
      ],
    ),
  );
}

void _webdavNotConfigured(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        context.l10n.d(
          'Stel eerst een WebDAV-server in bij Instellingen → WebDAV.',
        ),
      ),
    ),
  );
}

/// Maak een veilige bestandsnaam (zonder extensie) uit een deck-titel.
String _safeRemoteName(String title) {
  final cleaned = title
      .replaceAll(RegExp(r'[^\w\s-]'), '')
      .replaceAll(RegExp(r'\s+'), '_')
      .trim();
  return cleaned.isEmpty ? 'presentatie' : cleaned;
}

/// Keuze uit het opslaan-dialoog: formaat plus doelpad (zonder extensie,
/// relatief aan de wortelmap).
typedef _WebdavSaveChoice = ({WebdavSaveFormat format, String base});

Future<_WebdavSaveChoice?> _showWebdavSaveDialog(
  BuildContext context, {
  required String defaultBase,
}) {
  return showDialog<_WebdavSaveChoice>(
    context: context,
    builder: (_) => _WebdavSaveDialog(defaultBase: defaultBase),
  );
}

class _WebdavSaveDialog extends StatefulWidget {
  final String defaultBase;
  const _WebdavSaveDialog({required this.defaultBase});

  @override
  State<_WebdavSaveDialog> createState() => _WebdavSaveDialogState();
}

class _WebdavSaveDialogState extends State<_WebdavSaveDialog> {
  late final TextEditingController _path = TextEditingController(
    text: widget.defaultBase,
  );
  WebdavSaveFormat _format = WebdavSaveFormat.ocideck;

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Opslaan naar WebDAV')),
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
            RadioGroup<WebdavSaveFormat>(
              groupValue: _format,
              onChanged: (v) => setState(() => _format = v!),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<WebdavSaveFormat>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: WebdavSaveFormat.ocideck,
                    title: Text(
                      l10n.d('Als .ocideck-pakket (één bestand, met assets)'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  RadioListTile<WebdavSaveFormat>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: WebdavSaveFormat.flat,
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
              decoration: const InputDecoration(
                hintText: 'https://...',
                prefixIcon: Icon(Icons.link, size: 18),
                isDense: true,
                border: OutlineInputBorder(),
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
  final projectImagesPath = projectPath == null
      ? null
      : p.join(projectPath, 'images');
  // Projectmap eerst, dan alle bibliotheken als zoekwortels. De carousel scant
  // elke wortel recursief, dus diepe submappen komen automatisch mee.
  return [?projectImagesPath, ?projectPath, ...libraryPaths];
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
    for (var i = 0; i < deck.slides.length; i++) {
      final slide = deck.slides[i];
      for (final candidate in [slide.imagePath, slide.imagePath2]) {
        if (candidate.isEmpty) continue;
        final resolved = resolveSlideAssetPath(candidate, deck.projectPath);
        if (resolved == null) continue;
        if (p.normalize(resolved) == target) {
          usages.add('${tab.label} · slide ${i + 1}');
          break;
        }
      }
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

    String resolve(String candidate) =>
        resolveSlideAssetPath(candidate, deck.projectPath) ?? '';
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
      var updated = slide;
      if (slide.imagePath.isNotEmpty && resolve(slide.imagePath) == target) {
        updated = updated.copyWith(imagePath: replacement(slide.imagePath));
      }
      if (slide.imagePath2.isNotEmpty && resolve(slide.imagePath2) == target) {
        updated = updated.copyWith(imagePath2: replacement(slide.imagePath2));
      }
      if (!identical(updated, slide)) notifier.updateSlide(i, updated);
    }
  }
}

List<Slide> _slidesForPresentationOrExport(Deck deck) {
  // Drop skipped slides and slides whose TLP classification is stricter than
  // the level chosen for this presentation/export.
  final slides = deck.slides
      .where((s) => !s.skipped && slideVisibleAtTlp(s, deck.tlp))
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

/// Sla [deckNotifier] op. Voor een nieuw deck (nog geen bestandspad) toont dit
/// eerst een bestemmingsdialoog — kies een bibliotheek en zie waar de
/// presentatie, afbeeldingen en media landen — en opent daarna het
/// systeem-opslaanvenster in de gekozen map. Bestaande decks slaan direct op.
/// Op web (geen schrijfbaar bestandssysteem) is opslaan een download; dan geen
/// dialoog. Geeft terug of er daadwerkelijk is opgeslagen.
Future<bool> saveDeckWithDestination(
  BuildContext context,
  WidgetRef ref,
  DeckNotifier deckNotifier,
) async {
  final settings = ref.read(settingsProvider);
  final isNewDeck = deckNotifier.currentState.filePath == null;
  if (!isNewDeck || !supportsLocalProjectFolders) {
    return deckNotifier.save(initialDirectory: settings.homeDirectory);
  }
  final choice = await SaveDestinationDialog.show(
    context,
    libraries: settings.libraries,
    deckTitle: deckNotifier.currentState.deck?.title ?? '',
  );
  if (choice == null || !context.mounted) return false;
  return deckNotifier.save(initialDirectory: choice.directory);
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
    final choice = await _confirmSaveBeforeCloseDialog(
      context,
      context.l10n.d(
        'Deze presentatie heeft niet-opgeslagen wijzigingen. Sla de presentatie op voordat het tabblad sluit.',
      ),
    );
    if (!context.mounted) return;
    switch (choice) {
      case _CloseChoice.cancel:
        return;
      case _CloseChoice.discard:
        // Wijzigingen verwerpen: closeTab() ruimt ook het herstelbestand op.
        break;
      case _CloseChoice.save:
        final saved = await saveDeckWithDestination(
          context,
          ref,
          tab.deckNotifier,
        );
        if (!saved) return;
    }
  }
  ref.read(tabsProvider.notifier).closeTab(index);
}

/// Opent de fullscreen-presenter voor het open deck. Gedeeld door de
/// hoofd-toolbar en het 'alleen afspelen'-scherm zodat beide exact dezelfde
/// slide-filtering, annotatie-koppeling en fullscreen-overgang gebruiken.
///
/// Met [fromStart] begint de presentatie bij de eerste zichtbare slide; anders
/// bij de huidige selectie in de editor. Toont een melding en doet niets als er
/// (na filtering) geen slides zijn.
void presentDeck(
  BuildContext context,
  WidgetRef ref, {
  bool fromStart = false,
}) {
  final deckNotifier = ref.read(deckProvider.notifier);
  final deck = ref.read(deckProvider).deck;
  if (deck == null) return;
  final l10n = context.l10n;
  // Overgeslagen slides weglaten en de selectie naar de eerstvolgende
  // zichtbare slide vertalen.
  final visible = <int>[
    for (var i = 0; i < deck.slides.length; i++)
      if (!deck.slides[i].skipped &&
          slideVisibleAtTlp(deck.slides[i], deck.tlp))
        i,
  ];
  final slides = _slidesForPresentationOrExport(deck);
  if (slides.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.d('Alle slides zijn overgeslagen — niets om te tonen.'),
        ),
      ),
    );
    return;
  }
  int initial;
  if (fromStart) {
    initial = 0;
  } else {
    final selectedIndex = ref.read(editorProvider).selectedIndex;
    initial = visible.indexWhere((i) => i >= selectedIndex);
    if (initial < 0) initial = visible.length - 1;
    if (initial < 0) initial = 0;
  }
  final settings = ref.read(settingsProvider);
  // Render-time pagination: a long finding presents as several full-size slides
  // (matching the export). Remap the start index into the expanded list. A
  // finding never fires onSlideChanged (only checklist/table live-edits do), so
  // the callback below still resolves page-slides to their deck slide by id.
  final renderSlides = expandFindingsForRender(slides);
  final renderInitial = expandFindingsForRender(
    slides.sublist(0, initial),
  ).length.clamp(0, renderSlides.length - 1);
  FullscreenPresenter.present(
    context,
    // De projectiegrens. Presenteren is het ontvangende oppervlak bij uitstek:
    // wat hier op het scherm komt, ziet de zaal.
    audienceDeck: PrivacyProjection.forAudience(
      deck.copyWith(slides: renderSlides),
      disabledRules: settings.privacyDisabledRules,
      ownIdentity: OwnIdentity.fromLines(settings.privacyOwnIdentity),
    ),
    cockpitColorScheme: settings.cockpitColorScheme,
    initialIndex: renderInitial,
    showClassificationWatermark: settings.classificationWatermarkEnabled,
    allowRemoteMedia: settings.allowRemoteMedia,
    showRehearsalSummary: deck.showRehearsalSummary,
    targetDuration: () {
      final secs = deck.presentationTargetSeconds;
      return secs > 0 ? Duration(seconds: secs) : null;
    }(),
    annotations: deck.annotations,
    onAnnotationsChanged: deckNotifier.setAnnotations,
    initialUserNotes: deck.userNotes,
    onUserNotesChanged: deckNotifier.setUserNotes,
    onSlideChanged: (updated) {
      final index = deckNotifier.currentState.deck?.slides.indexWhere(
        (slide) => slide.id == updated.id,
      );
      if (index != null && index >= 0) {
        deckNotifier.updateSlide(index, updated);
      }
    },
  );
}

// ── App shell ─────────────────────────────────────────────────────────────────
