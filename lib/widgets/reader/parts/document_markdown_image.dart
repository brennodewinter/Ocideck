// Part of the document-markdown-view library — see ../document_markdown_view.dart.
//
// De afbeeldingskant van de documentweergave: de context die de map van het
// document draagt, de resolver die een markdown-pad omzet in een begrensde
// ImageProvider, en de widget die de afbeelding tekent (of een merkteken als
// het pad niet oplost). Losgeknipt om document_markdown_view.dart onder zijn
// regelplafond te houden.
part of '../document_markdown_view.dart';

/// Draagt de map van het document, zodat de lezer en het schrijfvlak een
/// afbeeldingspad op dezelfde manier oplossen — één renderwereld, net als
/// `DocumentStyleScope` dat voor het stijlprofiel doet.
///
/// Zonder deze scope (de documentatielezer, instellingenvoorvertoning, tests)
/// is [projectPath] `null` en lost `documentImageProvider` alleen `asset:`- en
/// `mem:`-paden op: een gebundelde afbeelding tekent, een relatief pad naar een
/// bestand naast het document niet. Dat is juist — die plekken hebben de map
/// niet, en een pad raden is erger dan het merkteken tonen.
class DocumentImageScope extends InheritedWidget {
  const DocumentImageScope({
    super.key,
    required this.projectPath,
    required super.child,
  });

  /// De map waarin het document staat, of `null` wanneer er geen is (nog niet
  /// opgeslagen, of een weergave die geen bestanden hoeft te lezen).
  final String? projectPath;

  static String? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DocumentImageScope>()
      ?.projectPath;

  @override
  bool updateShouldNotify(DocumentImageScope oldWidget) =>
      projectPath != oldWidget.projectPath;
}

/// Zet een markdown-afbeeldingspad [source] om in een begrensde
/// [ImageProvider] voor documentweergave, of `null` wanneer het niet oplost.
///
/// Hergebruikt dezelfde decode-grenzen als slides (`cappedFileImage`,
/// `cappedMemoryImage`, `cappedBundledAssetImage` — 4096 px / 64 MiB), dus een
/// document met twintig foto's eet het geheugen niet op. De pad-resolutie is
/// project-contained (`resolveSlideAssetPath`): een documentpad is invoer, geen
/// instructie, en een onvertrouwd document kan zo niet willekeurige bestanden
/// buiten zijn map lezen. Fail-closed: een ontbrekend of onoplosbaar pad geeft
/// `null`, en de aanroeper toont het merkteken in plaats van een leeg vlak.
///
/// Op web bestaat geen bestandssysteem: alleen `mem:` (via [WebAssetStore]) en
/// `asset:` (gebundeld) lossen op. Die grens staat in de gids, niet als raadsel.
ImageProvider? documentImageProvider(String source, String? projectPath) {
  if (source.isEmpty) return null;
  // Gebundeld asset (ingebouwde stijlprofielen): rendert op elk platform.
  if (isBundledAssetPath(source)) {
    return cappedBundledAssetImage(bundledAssetKey(source));
  }
  // mem: (webversie): bytes in de WebAssetStore in plaats van een bestand.
  if (WebAssetStore.isMemPath(source)) {
    final bytes = WebAssetStore.bytesFor(source);
    if (bytes == null) return null; // weg na een paginaherlaad
    return cappedMemoryImage(bytes);
  }
  // Lokaal bestand (desktop): project-contained, met de symlink-grens die slides
  // ook bewaken. Op web komt een bestandspad hier nooit aan — `resolveSlideAssetPath`
  // geeft daar `null` — maar de expliciete `kIsWeb`-tak maakt de grens leesbaar.
  if (kIsWeb) return null;
  final resolved = resolveSlideAssetPath(source, projectPath);
  if (resolved == null) return null;
  if (projectPath != null && !isRenderPathContained(resolved, projectPath)) {
    return null;
  }
  return cappedFileImage(File(resolved), version: imageVersionOf(resolved));
}

/// Tekent één afbeelding in de documentstroom, of het merkteken als het pad
/// niet oplost.
///
/// De hoogte komt uit de werkelijke afmeting: zodra de [ImageProvider] zijn
/// intrinsieke breedte/hoogte heeft, tekent een `AspectRatio` op de echte
/// verhouding — geen schatting die stil wegrot. Tot die tijd staat een
/// placeholder, en de paginaweergave hermeet zodra de afmeting binnenkomt.
///
/// Met [block] staat de afbeelding op eigen regel (volle breedte, met de
/// alinearuimte eronder); zonder [block] is hij inline in een tekstregel
/// (begrensd op de beschikbare regelbreedte), zoals het schrijfvlak hem toont.
class DocumentImage extends StatefulWidget {
  const DocumentImage({
    super.key,
    required this.source,
    required this.alt,
    required this.projectPath,
    this.block = true,
  });

  final String source;
  final String alt;
  final String? projectPath;
  final bool block;

  @override
  State<DocumentImage> createState() => _DocumentImageState();
}

class _DocumentImageState extends State<DocumentImage> {
  ImageProvider? _provider;
  double? _aspectRatio;
  bool _failed = false;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(DocumentImage old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source || old.projectPath != widget.projectPath) {
      _discardStream();
      _aspectRatio = null;
      _failed = false;
      _resolve();
    }
  }

  void _resolve() {
    final provider = documentImageProvider(widget.source, widget.projectPath);
    if (provider == null) {
      _provider = null;
      return;
    }
    _provider = provider;
    // Vraag de intrinsieke afmeting op, zodat de hoogte uit de echte verhouding
    // komt in plaats van uit een schatting. Luister leak-vrij: de listener gaat
    // er weer af in dispose / bij een nieuwe bron.
    final config = createLocalImageConfiguration(context, size: null);
    final stream = provider.resolve(config);
    _stream = stream;
    final listener = ImageStreamListener(
      (info, synchronous) {
        final w = info.image.width;
        final h = info.image.height;
        if (w > 0 && h > 0 && mounted) {
          setState(() => _aspectRatio = w / h);
        }
      },
      onError: (error, stackTrace) {
        if (mounted) setState(() => _failed = true);
      },
    );
    _listener = listener;
    stream.addListener(listener);
  }

  void _discardStream() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _discardStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    // Pad lost niet op, of de decodering faalde: het merkteken, niet leeg.
    // Een ontbrekend bestand hoort zichtbaar te zijn.
    if (provider == null || _failed) {
      return _DocumentImageChip(
        alt: widget.alt,
        source: widget.source,
        block: widget.block,
      );
    }
    final ratio = _aspectRatio;
    final image = ratio == null
        ? const _DocumentImagePlaceholder()
        : AspectRatio(
            aspectRatio: ratio,
            child: Image(
              image: provider,
              fit: BoxFit.contain,
              width: double.infinity,
              // Het vorige beeld blijft staan terwijl de volgende decodeert;
              // zonder dit flitst het vlak even zwart bij een bronwissel.
              gaplessPlayback: true,
              semanticLabel: widget.alt,
              errorBuilder: (context, error, stackTrace) => _DocumentImageChip(
                alt: widget.alt,
                source: widget.source,
                block: widget.block,
              ),
            ),
          );
    if (!widget.block) return image;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: kDocumentParagraphGap),
      child: image,
    );
  }
}

/// Het merkteken voor een afbeelding die niet te tonen is — de alt-tekst (of de
/// bestandsnaam) op een codevlakje, hetzelfde als in het schrijfvlak. Een leeg
/// vlak zou lezen als "vergeten", en dat is precies verkeerd om.
class _DocumentImageChip extends StatelessWidget {
  const _DocumentImageChip({
    required this.alt,
    required this.source,
    this.block = true,
  });

  final String alt;
  final String source;
  final bool block;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final ink = style.color ?? AppTheme.ink;
    final label = alt.trim().isNotEmpty ? alt.trim() : _fileName(source);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.inlineCodeBackground(ink),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, size: 18, color: ink),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 6),
            Flexible(child: Text(label, style: style)),
          ],
        ],
      ),
    );
    if (!block) return chip;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: kDocumentParagraphGap),
      child: chip,
    );
  }

  static String _fileName(String source) {
    final cut = source.lastIndexOf(RegExp(r'[/\\]'));
    return cut < 0 ? source : source.substring(cut + 1);
  }
}

/// Een laag, neutraal vlak terwijl de afmeting nog niet bekend is — zodat de
/// afbeelding niet van nul hoogte naar zijn echte maat springt, en de
/// paginaweergave een meetbare hoogte heeft tot de verhouding binnenkomt.
class _DocumentImagePlaceholder extends StatelessWidget {
  const _DocumentImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: scheme.primary,
          ),
        ),
      ),
    );
  }
}
