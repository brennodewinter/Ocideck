// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability (image rendering helpers, captions & placeholders); all imports live in the main
// library file. These top-level preview classes/helpers relocate verbatim
// from media_previews.dart — same library, no behaviour change.
part of '../slide_preview.dart';

/// Rendert een afbeelding met zoomfactor op basis van BoxFit.contain.
///   imageSize = 0   → cover (Marp-standaard, vult frame, snijdt bij)
///   imageSize = 100 → volledige afbeelding zichtbaar (contain, evt. randen)
///   imageSize > 100 → inzoomen: groter dan contain, bijgesneden door ClipRect
///   imageSize < 100 → nog meer uitzoomen: afbeelding kleiner dan contain
Widget _zoomedImage(
  BuildContext context,
  String imagePath,
  String? projectPath,
  int imageSize, {
  Color bgColor = Colors.black,
  Alignment alignment = Alignment.center,
  String? semanticLabel,
}) {
  if (imageSize == 0) {
    return _resolvedImage(
      context,
      imagePath,
      projectPath,
      // Cover crops the overflow; honour the focal point so the author can pick
      // which part of the picture stays in view instead of always centring.
      alignment: alignment,
      semanticLabel: semanticLabel,
    ); // BoxFit.cover standaard
  }
  // Defensive cap (parse already clamps): keep the scaled box bounded no matter
  // how imageSize was set, so an extreme value can't produce a huge layout box.
  final scale = imageSize.clamp(0, 400) / 100.0;
  // Size the image box to `scale` × the available area and let BoxFit.contain
  // fit the picture inside it. This produces the same visual result as a
  // Transform.scale but without a transform layer, which `RepaintBoundary
  // .toImage` (used for exports) captures far more reliably — a scaled
  // transform layer would frequently render blank in the exported PNG.
  return ClipRect(
    child: ColoredBox(
      color: bgColor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final boxW = constraints.maxWidth * scale;
          final boxH = constraints.maxHeight * scale;
          return Align(
            alignment: alignment,
            child: SizedBox(
              width: boxW,
              height: boxH,
              // BoxFit.contain: toont de volledige afbeelding zonder bijsnijden
              child: _resolvedImage(
                context,
                imagePath,
                projectPath,
                fit: BoxFit.contain,
                semanticLabel: semanticLabel,
              ),
            ),
          );
        },
      ),
    ),
  );
}

/// Alt text for a content image (WCAG 1.1.1): the per-usage [altText] when the
/// author set one (AI_ASSIST §6.1), else the visible caption, else a generic
/// "image" so a screen reader still announces that a picture is present (the
/// slide-quality analyzer nudges adding alt-text). Background/decorative images
/// pass `null` and stay out of the semantics tree.
String imageSemanticsLabel(
  BuildContext context,
  String caption, {
  String altText = '',
}) {
  final alt = altText.trim();
  if (alt.isNotEmpty) return alt;
  final text = caption.trim();
  return text.isEmpty ? context.l10n.d('Afbeelding') : text;
}

Widget _resolvedImage(
  BuildContext context,
  String imagePath,
  String? projectPath, {
  BoxFit fit = BoxFit.cover,
  Alignment alignment = Alignment.center,
  bool trustedAsset = false,
  String? semanticLabel,
}) {
  if (imagePath.isEmpty) {
    return _imagePlaceholder(context, ImagePlaceholderReason.noImage);
  }

  // Méégebundelde asset (ingebouwde stijlprofielen, bv. het LibreKAT-logo):
  // rendert op elk platform, ook op web waar geen bestandssysteem bestaat.
  if (isBundledAssetPath(imagePath)) {
    return Image(
      image: cappedBundledAssetImage(bundledAssetKey(imagePath)),
      fit: fit,
      alignment: alignment,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      semanticLabel: semanticLabel,
      errorBuilder: (context, error, stackTrace) =>
          _imagePlaceholder(context, ImagePlaceholderReason.missing),
    );
  }

  // In-memory afbeelding (webversie): een `mem:`-pad wijst naar bytes in de
  // WebAssetStore in plaats van naar een bestand. Zelfde decode-cap; na een
  // herlaad van de pagina is de store leeg en toont dit de placeholder.
  final memBytes = WebAssetStore.isMemPath(imagePath)
      ? WebAssetStore.bytesFor(imagePath)
      : null;
  if (memBytes != null) {
    return Image(
      image: cappedMemoryImage(memBytes),
      fit: fit,
      alignment: alignment,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      semanticLabel: semanticLabel,
      errorBuilder: (context, error, stackTrace) =>
          _imagePlaceholder(context, ImagePlaceholderReason.missing),
    );
  }
  if (WebAssetStore.isMemPath(imagePath)) {
    return _imagePlaceholder(context, ImagePlaceholderReason.memoryGone);
  }

  // Online afbeelding: render live via NetworkImage (zelfde decode-cap als
  // bestanden), maar alleen als de remote-media-gate open staat én de URL door
  // de SSRF-gate komt. Anders een placeholder met de URL.
  if (VideoSource.looksLikeUrl(imagePath)) {
    if (!_SlideLinkScope.allowRemoteMediaOf(context)) {
      return _remoteBlockedPlaceholder(context, imagePath);
    }
    // Resolve the host before fetching: a remote image whose host maps to an
    // internal address is an SSRF probe (NetGuard.isAllowedMediaUrlResolved),
    // so gate the NetworkImage on the async result and show a placeholder
    // while it resolves / when it is refused.
    return FutureBuilder<bool>(
      future: NetGuard.isAllowedMediaUrlResolved(imagePath),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _imagePlaceholder(context, ImagePlaceholderReason.noImage);
        }
        if (snapshot.data != true) {
          return _remoteBlockedPlaceholder(context, imagePath);
        }
        return Image(
          image: cappedNetworkImage(imagePath),
          fit: fit,
          alignment: alignment,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          semanticLabel: semanticLabel,
          errorBuilder: (context, error, stackTrace) =>
              _imagePlaceholder(context, ImagePlaceholderReason.missing),
        );
      },
    );
  }

  // The logo is trusted style-profile config and may live outside the opened
  // deck's project folder; slide images stay project-contained (untrusted deck
  // content must not read arbitrary files).
  final resolved = trustedAsset
      ? resolveTrustedAssetPath(imagePath, projectPath)
      : resolveSlideAssetPath(imagePath, projectPath);
  if (resolved == null) {
    // Op web bestaat er geen bestandssysteem: het bestand is er domweg niet.
    // Op desktop kan dit alleen door de containment-grens komen.
    return _imagePlaceholder(
      context,
      kIsWeb
          ? ImagePlaceholderReason.missing
          : ImagePlaceholderReason.outsideDeck,
    );
  }
  // Block a project-internal symlink that points outside the project (cached,
  // so the per-frame cost is O(1) after the first render of each image).
  if (!trustedAsset &&
      projectPath != null &&
      !isRenderPathContained(resolved, projectPath)) {
    return _imagePlaceholder(context, ImagePlaceholderReason.outsideDeck);
  }

  return Image(
    // Cap the decode so a huge-dimensioned (possibly untrusted) image can't
    // exhaust memory; see cappedFileImage / kMaxImageDecodeDimension.
    image: cappedFileImage(File(resolved)),
    fit: fit,
    alignment: alignment,
    width: double.infinity,
    height: double.infinity,
    semanticLabel: semanticLabel,
    // Keep showing the previous frame while the next image decodes. Without
    // this the widget paints nothing for a frame on a source change, which
    // shows up as a black flash between slides — fatal when recording video.
    gaplessPlayback: true,
    errorBuilder: (context, error, stackTrace) =>
          _imagePlaceholder(context, ImagePlaceholderReason.missing),
  );
}

Widget _captionOverlay(
  BuildContext context,
  String caption,
  double w, {
  double? right,
  double? bottom,
}) {
  final text = caption.trim();
  if (text.isEmpty) return const SizedBox.shrink();
  // Een copyright/bijschrift staat rechtsonder; als daar een TLP-markering
  // staat, schuift het bijschrift erboven zodat het niet wordt overschreven.
  final lift = _SlideLinkScope.hasBottomTlpOf(context)
      ? _tlpVerticalReserve(w)
      : 0.0;
  return Positioned(
    right: right ?? w * _kTlpEdge,
    bottom: (bottom ?? _tlpBottomInset(w)) + lift,
    child: Container(
      constraints: BoxConstraints(maxWidth: w * 0.5),
      padding: EdgeInsets.symmetric(horizontal: w * 0.008, vertical: w * 0.005),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(
          color: Colors.white,
          fontSize: w * 0.011,
          height: 1.25,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}

/// Placeholder voor online media die niet live geladen wordt (de remote-media-
/// gate staat uit, of de URL is afgekeurd). Toont de URL zodat de gebruiker ziet
/// waar de media vandaan zou komen, plus een hint dat online media uit staat.
Widget _remoteBlockedPlaceholder(BuildContext context, String url) {
  return Container(
    color: AppTheme.slate200,
    padding: const EdgeInsets.all(16),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, color: AppTheme.slate400, size: 32),
          const SizedBox(height: 8),
          Text(
            context.l10n.d('Online media staat uit'),
            style: TextStyle(
              color: AppTheme.slate500,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            url,
            style: TextStyle(color: AppTheme.slate400, fontSize: 10),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );
}

Widget _mediaPlaceholder(IconData icon, String label) {
  return Container(
    color: AppTheme.slate200,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.slate400, size: 32),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: AppTheme.slate400, fontSize: 12)),
        ],
      ),
    ),
  );
}

/// Waarom er geen afbeelding staat.
///
/// Deze vier gevallen zagen er tot nu toe identiek uit: hetzelfde grijze vlak
/// met het woord "Afbeelding". Dat is precies verkeerd om — een leeg veld is
/// werk dat nog moet gebeuren, een ontbrekend bestand is een presentatie die
/// stuk is, en dat verschil moet je kunnen zien zonder de code te kennen.
enum ImagePlaceholderReason {
  /// Er is nog geen afbeelding gekozen.
  noImage,

  /// Er is een verwijzing, maar het bestand is er niet (meer).
  missing,

  /// Het pad wijst buiten de presentatiemap en wordt daarom niet geladen.
  outsideDeck,

  /// Webversie: de afbeelding stond alleen in het geheugen en de pagina is
  /// herladen.
  memoryGone,
}

Widget _imagePlaceholder(BuildContext context, ImagePlaceholderReason reason) {
  final (icon, label) = switch (reason) {
    ImagePlaceholderReason.noImage => (
      Icons.image_outlined,
      context.l10n.d('Afbeelding'),
    ),
    ImagePlaceholderReason.missing => (
      Icons.broken_image_outlined,
      context.l10n.d('Bestand niet gevonden'),
    ),
    ImagePlaceholderReason.outsideDeck => (
      Icons.link_off,
      context.l10n.d('Buiten de presentatie'),
    ),
    ImagePlaceholderReason.memoryGone => (
      Icons.broken_image_outlined,
      context.l10n.d('Weg na herladen'),
    ),
  };

  return ColoredBox(
    color: AppTheme.slate200,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = constraints.biggest.shortestSide;
        if (shortestSide < 48) {
          return Center(
            child: Icon(
              icon,
              color: AppTheme.slate400,
              size: shortestSide * 0.65,
            ),
          );
        }

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppTheme.slate400, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(color: AppTheme.slate400, fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    ),
  );
}
