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
  if (result == null) return;
  await ref
      .read(tabsProvider.notifier)
      .openFileByPath(result.path, selectIndex: result.slideIndex);
}

/// Vraag een URL op om een presentatie (pakket of markdown) op te halen.
Future<String?> _showUrlDialog(BuildContext context) {
  final l10n = context.l10n;
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
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
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'https://…',
                prefixIcon: Icon(Icons.link, size: 18),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.t('cancel')),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(ctx, controller.text),
          icon: const Icon(Icons.download, size: 16),
          label: Text(l10n.d('Ophalen')),
        ),
      ],
    ),
  );
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
