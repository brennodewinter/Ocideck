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
    // Een leeg pad heeft twee heel verschillende betekenissen, en alleen de
    // scope weet welke: de auteur heeft nog niets gekozen, óf de projectie
    // heeft de afbeelding weggehaald. Zie `_SlideLinkScope.mediaRedacted`.
    return _imagePlaceholder(
      context,
      _SlideLinkScope.mediaRedactedOf(context)
          ? ImagePlaceholderReason.redacted
          : ImagePlaceholderReason.noImage,
    );
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
          image: guardedNetworkImage(imagePath),
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

  // Cap the decode so a huge-dimensioned (possibly untrusted) image can't
  // exhaust memory; see cappedFileImage / kMaxImageDecodeDimension. De
  // slidestrook zet daarbovenop een veel lagere grens via de scope — daar is
  // een thumbnail van ~180 px breed, en op ware grootte kost één telefoonfoto
  // bijna 49 MiB (#612).
  final maxEdge = _SlideLinkScope.decodeMaxEdgeOf(context);
  return Image(
    image: maxEdge == null
        ? cappedFileImage(File(resolved))
        : boundedFileImage(File(resolved), maxEdge),
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

/// Waaróm online media niet live geladen wordt — de drie gevallen die elk een
/// eigen melding (en wel/geen instelling-sprong) verdienen.
enum RemoteBlockedReason {
  /// Op web blokkeert de browser externe media sowieso (de web-CSP), ongeacht de
  /// instelling. Aanzetten helpt daar niet.
  web,

  /// De instelling 'online media' staat uit (de desktop-standaard). Hier hoort
  /// de sprong naar Instellingen → Beveiliging.
  settingOff,

  /// De instelling staat aan, maar de bron-URL is door de beveiliging (de
  /// SSRF-gate) afgewezen. Aanzetten is al gebeurd; het ligt aan de URL.
  urlRejected,
}

/// Bepaalt de reden uit het platform en de instelling. Puur en publiek zodat een
/// test de drie gevallen — inclusief het web-geval dat onder `flutter test` niet
/// vanzelf ontstaat — kan vastpinnen zonder de widgetboom.
@visibleForTesting
RemoteBlockedReason remoteBlockedReasonFor({
  required bool isWeb,
  required bool allowRemoteMedia,
}) {
  if (isWeb) return RemoteBlockedReason.web;
  if (!allowRemoteMedia) return RemoteBlockedReason.settingOff;
  return RemoteBlockedReason.urlRejected;
}

/// Placeholder voor online media die niet live geladen wordt. Toont de URL zodat
/// de gebruiker ziet waar de media vandaan zou komen, plus een reden die past
/// bij wáárom het niet speelt — en, waar dat helpt, een sprong naar de
/// instelling (#852).
///
/// Drie situaties, elk met een eigen eerlijke reden:
///  * **web** — de browser blokkeert media van een externe bron, ongeacht de
///    instelling (de web-CSP van `web/index.html`). Aanzetten helpt daar niet,
///    dus geen knop; de melding benoemt het webspecifieke gedrag.
///  * **de instelling staat uit** — de gewone desktop-standaard, bewust uit voor
///    de privacy. Hier hoort de sprong naar Instellingen → Beveiliging, maar
///    alleen in de editor-preview (daar zet [_SlideLinkScope.onEnableOnlineMedia]
///    de callback; in presenter/thumbnails/export/play-only is hij null).
///  * **de instelling staat aan maar de URL is geweigerd** — de SSRF-gate wees
///    de bron af. Aanzetten is al gebeurd; het ligt aan de URL, dus geen knop.
Widget _remoteBlockedPlaceholder(BuildContext context, String url) {
  final l10n = context.l10n;
  final reason = remoteBlockedReasonFor(
    isWeb: kIsWeb,
    allowRemoteMedia: _SlideLinkScope.allowRemoteMediaOf(context),
  );

  final String title;
  String? detail;
  VoidCallback? onEnable;
  switch (reason) {
    case RemoteBlockedReason.web:
      title = l10n.d('Online media werkt niet in de webversie');
      detail = l10n.d(
        'De browser blokkeert media van een externe bron. Open deze presentatie in de app om online media te tonen.',
      );
    case RemoteBlockedReason.settingOff:
      title = l10n.d('Online media staat uit');
      // De sprong naar de instelling bestaat alleen in de editor-preview.
      onEnable = _SlideLinkScope.onEnableOnlineMediaOf(context);
    case RemoteBlockedReason.urlRejected:
      title = l10n.d('Bron niet toegestaan');
      detail = l10n.d('Deze URL is door de beveiliging geweigerd.');
  }

  return Container(
    color: AppTheme.slideRuleSoft,
    padding: const EdgeInsets.all(16),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            color: AppTheme.slideInkSoft,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              color: AppTheme.slideInkMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(
              detail,
              style: TextStyle(color: AppTheme.slideInkSoft, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 4),
          Text(
            url,
            style: TextStyle(color: AppTheme.slideInkMuted, fontSize: 10),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (onEnable != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onEnable,
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: Text(l10n.d('Aanzetten in instellingen')),
              // Const dia-inkt, geen mode-afhankelijke UI-accent: wat op een dia
              // landt volgt het app-thema niet (zie slide_content_theme_
              // independent_test). Het icoon maakt de knop herkenbaar zonder
              // accentkleur.
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.slideInk,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Het vak voor video en audio zonder bron.
///
/// Neemt een [context] om dezelfde reden als [_resolvedImage]: een geredigeerde
/// video is óók media die is weggehaald, en die hoort hetzelfde zwarte vlak te
/// krijgen als een geredigeerde foto. Zonder deze tak toont een geredigeerde
/// videoslide een grijs vak met het woord "Video" — hetzelfde gat, andere naam.
Widget _mediaPlaceholder(BuildContext context, IconData icon, String label) {
  if (_SlideLinkScope.mediaRedactedOf(context)) {
    return _redactedMediaPlaceholder(context);
  }
  return Container(
    color: AppTheme.slideRuleSoft,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.slideInkSoft, size: 32),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(color: AppTheme.slideInkMuted, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

/// Waarom er geen afbeelding staat.
///
/// Deze gevallen zagen er tot nu toe identiek uit: hetzelfde grijze vlak
/// met het woord "Afbeelding". Dat is precies verkeerd om — een leeg veld is
/// werk dat nog moet gebeuren, een ontbrekend bestand is een presentatie die
/// stuk is, en dat verschil moet je kunnen zien zonder de code te kennen.
enum ImagePlaceholderReason {
  /// Er is nog geen afbeelding gekozen.
  noImage,

  /// De privacyprojectie heeft de afbeelding weggehaald.
  ///
  /// Dit is de enige reden die geen grijs vak krijgt maar een zwart. Een
  /// geredigeerde foto onder hetzelfde lichte "Afbeelding"-vak als een lege
  /// plek zetten leest als vergeetachtigheid, terwijl de tekst ernaast wél
  /// zwarte blokken toont — en de ontvanger die het verschil niet ziet, kan het
  /// verschil ook niet controleren. Zie `privacy_projection.dart`.
  redacted,

  /// Er is een verwijzing, maar het bestand is er niet (meer).
  missing,

  /// Het pad wijst buiten de presentatiemap en wordt daarom niet geladen.
  outsideDeck,

  /// Webversie: de afbeelding stond alleen in het geheugen en de pagina is
  /// herladen.
  memoryGone,
}

/// Het vlak dat in de plaats komt van weggeredigeerde media.
///
/// Zwart en dekkend, want dat is wat "geredigeerd" er in elk vrijgegeven
/// document uitziet, en het is dezelfde taal als de `█`-blokken die de
/// tekstredactie gebruikt (`kRedactionToken` in `privacy_projection.dart`).
/// Grijs zou hier niet alleen lelijk zijn maar onwaar: grijs is in deze app de
/// kleur van "er staat nog niets". Waaróm die kleuren de themastand niet volgen
/// staat bij [AppTheme.redactionInk].
///
/// Het label erbij, en niet alleen het vlak, omdat een zwart vlak op een dia
/// ook een ontwerpkeuze kan zijn. De ontvanger hoort te kunnen zien dát hier is
/// ingegrepen — dat is het hele punt van redigeren in plaats van weglaten.
/// Onder de 48 px is er geen ruimte voor tekst en blijft het vlak met het
/// icoon over; onder de 16 px alleen het vlak.
Widget _redactedMediaPlaceholder(BuildContext context) {
  return ColoredBox(
    color: AppTheme.redactionInk,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = constraints.biggest.shortestSide;
        if (shortestSide < 16) return const SizedBox.expand();
        if (shortestSide < 48) {
          return Center(
            child: Icon(
              Icons.block,
              color: AppTheme.redactionMark,
              size: shortestSide * 0.5,
            ),
          );
        }

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block, color: AppTheme.redactionMark, size: 24),
              const SizedBox(height: 4),
              Text(
                context.l10n.d('Geredigeerd'),
                style: TextStyle(
                  color: AppTheme.redactionMark,
                  fontSize: 10,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    ),
  );
}

Widget _imagePlaceholder(BuildContext context, ImagePlaceholderReason reason) {
  if (reason == ImagePlaceholderReason.redacted) {
    return _redactedMediaPlaceholder(context);
  }

  final (icon, label) = switch (reason) {
    // `redacted` is hierboven al afgevangen en komt hier nooit; de tak staat er
    // omdat Dart de switch volledig wil hebben.
    ImagePlaceholderReason.redacted || ImagePlaceholderReason.noImage => (
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

  // De drie plaatshouders in dit bestand vullen zich met `slideRuleSoft` en
  // zetten er tekst op. Die tekst stond op `slideInkFaint`: 4,4:1 op wit, maar
  // **2,08:1** op deze eigen tint (#780) — en dit is geen decoratie. "Bestand
  // niet gevonden", "Online media staat uit" en de URL erbij zijn het enige
  // wat vertelt waaróm er een grijs vlak op de dia staat, en ze reizen mee de
  // export in. Tekst dus op `slideInkMuted` (6,15:1), pictogram op
  // `slideInkSoft` (3,86:1 — grafisch object, WCAG 1.4.11).
  return ColoredBox(
    color: AppTheme.slideRuleSoft,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = constraints.biggest.shortestSide;
        if (shortestSide < 48) {
          return Center(
            child: Icon(
              icon,
              color: AppTheme.slideInkSoft,
              size: shortestSide * 0.65,
            ),
          );
        }

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppTheme.slideInkSoft, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(color: AppTheme.slideInkMuted, fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    ),
  );
}
