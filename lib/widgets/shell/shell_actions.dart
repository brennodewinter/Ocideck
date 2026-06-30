// Part of the app_shell library — see ../app_shell.dart.
// Split out for navigability; all imports live in the main library file.
part of '../app_shell.dart';

/// Open the search-based presentation picker and load the chosen file
/// (optionally jumping to a matched slide).
Future<void> _openWithSearch(
  BuildContext context,
  WidgetRef ref,
  String? initialDirectory,
) async {
  final settings = ref.read(settingsProvider);
  final result = await OpenPresentationDialog.show(
    context,
    fileService: ref.read(fileServiceProvider),
    initialDirectory: initialDirectory ?? settings.homeDirectory,
  );
  if (result == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final openResult = await ref
      .read(tabsProvider.notifier)
      .openFileByPath(result.path, selectIndex: result.slideIndex);
  // A loose .md browsed from disk that isn't a Marp/OciDeck presentation (or is
  // otherwise unreadable) is refused by openDeck — tell the user instead of
  // silently doing nothing. OpenResult.blocked already shows the security alarm.
  if (openResult == OpenResult.unreadable) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.d('Kon dit bestand niet openen.'))),
    );
  }
}

/// Scan a fixed set of well-known folders for Marp presentations and open the
/// chosen one. Complements [_openWithSearch], which scans a single folder.
Future<void> _scanLibrary(BuildContext context, WidgetRef ref) async {
  final path = await ScanLibraryDialog.show(
    context,
    fileService: ref.read(fileServiceProvider),
    recentFiles: ref.read(settingsProvider).recentFiles,
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
  if (url == null || url.trim().isEmpty) return;
  final ok = await ref
      .read(tabsProvider.notifier)
      .importFromUrl(url, homeDir: ref.read(settingsProvider).homeDirectory);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.d('Kon van deze URL geen presentatie ophalen.'),
        ),
      ),
    );
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
    if (result == OpenResult.unreadable) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.d('Kon dit bestand niet openen.'))),
      );
    }
    // OpenResult.blocked toont al het veiligheidsalarm via de shell.
  } on WebdavException catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('${l10n.d('Downloaden mislukt:')} ${e.message}')),
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
  final choice = await _showWebdavSaveDialog(context, defaultBase: defaultBase);
  if (choice == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final ext = choice.format == WebdavSaveFormat.ocideck ? '.ocideck' : '.md';
  final targetPath = '${choice.base}$ext';
  try {
    await ref
        .read(tabsProvider.notifier)
        .saveToWebdav(
          tab,
          service,
          format: choice.format,
          targetPath: targetPath,
        );
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('${l10n.d('Opgeslagen op Nextcloud:')} /$targetPath'),
      ),
    );
  } on WebdavException catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('${l10n.d('Opslaan mislukt:')} ${e.message}')),
    );
  }
}

void _webdavNotConfigured(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        context.l10n.d(
          'Stel eerst een Nextcloud-server in bij Instellingen → Nextcloud.',
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
      title: Text(l10n.d('Opslaan naar Nextcloud')),
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
                hintText: 'map/presentatie',
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
  void dispose() {
    _controller.dispose();
    super.dispose();
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
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
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
              onSubmitted: (v) => Navigator.pop(context, v),
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
          onPressed: () => Navigator.pop(context, _controller.text),
          icon: const Icon(Icons.download, size: 16),
          label: Text(l10n.d('Ophalen')),
        ),
      ],
    );
  }
}

List<String> _imageSearchPaths(String? projectPath, String? homeDirectory) {
  final projectImagesPath = projectPath == null
      ? null
      : p.join(projectPath, 'images');
  return [?projectImagesPath, ?projectPath, ?homeDirectory];
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

// ── App shell ─────────────────────────────────────────────────────────────────
