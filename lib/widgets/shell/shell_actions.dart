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
    _reportOpenFailure(messenger, l10n, result);
  } on GitForgeException catch (e) {
    // De uitzondering draagt al een uitlegbare tekst; die is voor de gebruiker
    // bedoeld, dus toon hem in plaats van een eigen samenvatting.
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// Blader door de Nextcloud/WebDAV-bron, download het gekozen deck, haal het
/// door de security-gate en open het in een tab. Toont waar nodig een melding.
Future<void> _openFromNextcloud(
  BuildContext context,
  WidgetRef ref, {
  WebdavConnection? connection,
}) async {
  final chosen = connection ?? await _pickWebdavConnection(context, ref);
  if (chosen == null || !context.mounted) return;
  final service = await ref.read(webdavServiceProvider(chosen.id).future);
  if (!context.mounted) return;
  if (service == null) {
    _webdavNotConfigured(context);
    return;
  }
  final entry = await WebdavBrowserDialog.show(
    context,
    connectionId: chosen.id,
  );
  if (entry == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    final result = await ref
        .read(tabsProvider.notifier)
        .openFromWebdav(
          service,
          entry,
          connectionId: chosen.id,
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
/// Slaat het actieve deck op naar WebDAV. Geeft terug of er daadwerkelijk is
/// opgeslagen.
///
/// Met [silent] slaat dit de naam- en formaatvraag over wanneer het deck van
/// deze server kwam: dan gaat het terug naar exact hetzelfde pad, in hetzelfde
/// formaat. Dat is wat de gewone opslaanknop doet — die hoort niet elke keer
/// opnieuw te vragen waar iets heen moet dat al ergens vandaan komt. Een
/// botsing met een nieuwere versie vraagt nog steeds, want dat is een keuze die
/// alleen de gebruiker kan maken.
Future<bool> _saveToNextcloud(
  BuildContext context,
  WidgetRef ref, {
  bool silent = false,
  WebdavConnection? connectionOverride,
}) async {
  final tab = ref.read(tabsProvider).current;
  final deck = tab?.deckNotifier.currentState.deck;
  if (tab == null || deck == null) return false;
  // Kwam dit deck van een WebDAV-verbinding die nog bestaat, dan gaat het
  // daarnaartoe terug zonder te vragen. Opnieuw laten kiezen zou de gebruiker
  // elke keer de kans geven het bij de verkeerde klant te laten belanden.
  final origin = tab.webdavOrigin;
  final settings = ref.read(settingsProvider);
  final known = settings.connectionById(origin?.connectionId);
  // Een expliciet gekozen doel wint van de herkomst: dat is precies wat
  // "Opslaan naar…" betekent.
  final connection =
      connectionOverride ??
      (known is WebdavConnection && known.isConfigured
          ? known
          : await _pickWebdavConnection(context, ref));
  if (connection == null || !context.mounted) return false;

  final service = await ref.read(webdavServiceProvider(connection.id).future);
  if (!context.mounted) return false;
  if (service == null) {
    _webdavNotConfigured(context);
    return false;
  }
  // Standaardpad: hergebruik de herkomst als die van dezelfde server komt,
  // anders een nette bestandsnaam uit de deck-titel in de wortelmap.
  final reuse = origin != null && origin.matchesServer(service.server);
  final defaultBase = reuse
      ? origin.remotePath.replaceAll(RegExp(r'\.(ocideck|zip|md)$'), '')
      : _safeRemoteName(deck.title);
  var choice = silent && reuse
      ? (format: _formatOfRemotePath(origin.remotePath), base: defaultBase)
      : await _showRemoteSaveDialog(
          context,
          defaultBase: defaultBase,
          title: context.l10n.d('Opslaan naar WebDAV'),
        );
  if (choice == null || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  // Blijft doorlopen zolang de gebruiker na een botsing een andere weg kiest:
  // onder een nieuwe naam opslaan, of alsnog overschrijven.
  var overwrite = false;
  while (true) {
    final ext = choice!.format == DeckSaveFormat.ocideck ? '.ocideck' : '.md';
    final targetPath = '${choice.base}$ext';
    try {
      await ref
          .read(tabsProvider.notifier)
          .saveToWebdav(
            tab,
            service,
            connectionId: connection.id,
            format: choice.format,
            targetPath: targetPath,
            overwrite: overwrite,
          );
      // Het opslaan is geslaagd; alleen de melding kan niet meer getoond worden.
      if (!context.mounted) return true;
      messenger.showSnackBar(
        SnackBar(
          content: Text('${l10n.d('Opgeslagen op WebDAV:')} /$targetPath'),
        ),
      );
      return true;
    } on WebdavConflictException catch (e) {
      logWarning('shell: WebDAV-opslaan botste met een nieuwere versie', e);
      if (!context.mounted) return false;
      final resolution = await _showRemoteConflictDialog(context);
      if (resolution == null || !context.mounted) return false;
      switch (resolution) {
        case _RemoteConflict.overwrite:
          overwrite = true;
        case _RemoteConflict.saveAs:
          final next = await _showRemoteSaveDialog(
            context,
            defaultBase: choice.base,
            title: l10n.d('Opslaan naar WebDAV'),
          );
          if (next == null || !context.mounted) return false;
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
      return false;
    }
  }
}

/// Het opslagformaat dat bij [remotePath] hoort. Een deck dat als pakket op de
/// server stond, gaat als pakket terug; een platte spiegel blijft plat.
DeckSaveFormat _formatOfRemotePath(String remotePath) =>
    remotePath.toLowerCase().endsWith('.ocideck')
    ? DeckSaveFormat.ocideck
    : DeckSaveFormat.flat;

/// Wat de gebruiker doet als het bestand op de server inmiddels van iemand
/// anders is. Bewust geen samenvoegkeuze zoals bij git: die leunt erop dat de
/// basisversie nog opvraagbaar is, en bij WebDAV en S3 is die weg zodra de
/// ander heeft geüpload.
enum _RemoteConflict { saveAs, overwrite }

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
String _safeRemoteName(String title) {
  final cleaned = title
      .replaceAll(RegExp(r'[^\w\s-]'), '')
      .replaceAll(RegExp(r'\s+'), '_')
      .trim();
  return cleaned.isEmpty ? 'presentatie' : cleaned;
}

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
