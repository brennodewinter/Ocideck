import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../models/deck.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../state/deck_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/settings_provider.dart';
import '../../services/finding_context_score.dart';
import '../../services/privacy/privacy_own_identity.dart';
import '../../services/privacy/privacy_preview.dart';
import '../../services/finding_pagination.dart';
import '../../services/rich_text_layout.dart';
import '../../services/slide_layout_metrics.dart';
import '../../theme/app_theme.dart';
import '../../utils/url_launcher_util.dart';
import '../../l10n/app_localizations.dart';
import '../slides/slide_preview.dart';

/// Of het preview-paneel ingeklapt is (UI-voorkeur, app-breed).
final previewCollapsedProvider = StateProvider<bool>((_) => false);

/// Huidige rich-text-pagina (0-gebaseerd) in het preview-paneel; gedeeld met
/// notitievelden in de editor.
final richTextPreviewPageProvider = StateProvider<int>((_) => 0);

/// Of de preview de dia toont zoals de zaal en de export hem krijgen, in plaats
/// van de eigen tekst van de auteur.
///
/// **Standaard uit, en dat is de hele opzet.** De auteur moet zijn eigen tekst
/// kunnen zien om hem te kunnen wijzigen; een preview die zwarte blokken toont
/// waar zijn zin stond, maakt bewerken onmogelijk. De schakelaar staat er om te
/// kunnen *controleren*, niet om in te werken — en hij verschijnt alleen op een
/// dia waar er iets te controleren valt.
final audiencePreviewProvider = StateProvider<bool>((_) => false);

class PreviewPanel extends ConsumerStatefulWidget {
  const PreviewPanel({super.key});

  @override
  ConsumerState<PreviewPanel> createState() => _PreviewPanelState();
}

class _PreviewPanelState extends ConsumerState<PreviewPanel> {
  final TransformationController _transform = TransformationController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'PreviewPanel');
  double _zoom = 1.0;
  String? _richTextSlideId;

  static const double _minZoom = 1.0;
  static const double _maxZoom = 4.0;
  static const double _zoomStep = 0.5;

  @override
  void dispose() {
    _transform.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Verplaats de slideselectie of rich-text-pagina met de pijltjestoetsen.
  void _move(int delta) {
    final deck = ref.read(deckProvider).deck;
    if (deck == null) return;
    final current = ref.read(editorProvider).selectedIndex;
    final slide = deck.slides[current.clamp(0, deck.slides.length - 1)];

    // A rich-text slide and an overflowing finding both preview as multiple
    // pages; arrow keys step through the pages before moving to the next slide.
    final pages = slideUsesRichText(slide)
        ? richTextPageCountForSlide(
            slide: slide,
            profile: deck.themeProfile,
            splitWithImage: slide.type.splitWithImage,
          )
        : expandFindingsForRender([slide]).length;
    if (pages > 1) {
      final page = ref.read(richTextPreviewPageProvider);
      if (delta > 0 && page < pages - 1) {
        ref.read(richTextPreviewPageProvider.notifier).state = page + 1;
        return;
      }
      if (delta < 0 && page > 0) {
        ref.read(richTextPreviewPageProvider.notifier).state = page - 1;
        return;
      }
    }

    final next = (current + delta).clamp(0, deck.slides.length - 1);
    if (next != current) {
      ref.read(editorProvider.notifier).select(next);
      ref.read(richTextPreviewPageProvider.notifier).state = 0;
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.pageUp:
        _move(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.pageDown:
        _move(1);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  void _zoomIn() {
    final next = (_zoom + _zoomStep).clamp(_minZoom, _maxZoom);
    _applyZoom(next);
  }

  void _zoomOut() {
    final next = (_zoom - _zoomStep).clamp(_minZoom, _maxZoom);
    _applyZoom(next);
  }

  void _resetZoom() {
    _applyZoom(_minZoom);
  }

  void _applyZoom(double zoom) {
    setState(() => _zoom = zoom);
    _transform.value = Matrix4.identity()..scaleByDouble(zoom, zoom, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Alleen het deck zelf: wissels in isDirty/canUndo/canRedo horen de
    // preview niet te herbouwen.
    final deck = ref.watch(deckProvider.select((s) => s.deck))!;
    final editor = ref.watch(editorProvider);
    final settings = ref.watch(settingsProvider);

    final idx = editor.selectedIndex.clamp(0, deck.slides.length - 1);
    final slide = deck.slides[idx];
    final richTextPage = ref.watch(richTextPreviewPageProvider);

    if (_richTextSlideId != slide.id) {
      _richTextSlideId = slide.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(richTextPreviewPageProvider.notifier).state = 0;
      });
    }

    final richTextPages = slideUsesRichText(slide)
        ? richTextPageCountForSlide(
            slide: slide,
            profile: deck.themeProfile,
            splitWithImage: slide.type.splitWithImage,
          )
        : 1;
    // A long finding previews across multiple full-size pages (render-time
    // pagination, mirroring the export); the preview shows the current page and
    // arrow keys / the page indicator step through them.
    final findingPageSlides = expandFindingsForRender([slide]);
    final isPagedFinding = findingPageSlides.length > 1;
    final pageCount = isPagedFinding ? findingPageSlides.length : richTextPages;
    final hasRichTextPages = pageCount > 1;
    final previewPage = richTextPage.clamp(0, pageCount - 1);
    final sourceSlide = isPagedFinding ? findingPageSlides[previewPage] : slide;
    // De publieksweergave: dezelfde projectie die presenteren en exporteren
    // gebruiken, maar op één dia — zie [audiencePreviewOf] voor waarom niet op
    // het hele deck.
    final redacted = slideIsRedacted(deck, slide);
    final showAudience = redacted && ref.watch(audiencePreviewProvider);
    final audience = showAudience
        ? audiencePreviewOf(
            deck,
            sourceSlide,
            disabledRules: settings.privacyDisabledRules,
            regions: settings.privacyRegions,
            ownIdentity: OwnIdentity.fromLines(settings.privacyOwnIdentity),
          )
        : null;
    final canvasSlide = audience?.slides.first ?? sourceSlide;
    // De organisatienaam in de voettekst is net zo goed tekst die de zaal leest,
    // en de projectie redigeert hem (privacy_projection.dart) — het
    // presenteerscherm haalt hem al uit het geprojecteerde deck. Alleen dát veld
    // wordt overgenomen: de rest van [deck] draagt de structuur (alle dia's, voor
    // de nummering en de gedeelde krimpfactor), en die zit niet in een
    // projectie van één dia.
    final canvasDeck = audience == null
        ? deck
        : deck.copyWith(organization: audience.deck.organization);

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: _focusNode.requestFocus,
        child: Container(
          color: AppTheme.slate100,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──────────────────────────────────────────────────────
              _header(
                l10n,
                deck,
                idx,
                previewPage,
                pageCount,
                hasRichTextPages,
              ),
              const Divider(height: 1),

              // ── Redactiemelding ──────────────────────────────────────────────
              if (redacted) _redactionNotice(l10n, showAudience),

              // ── Slide canvas ─────────────────────────────────────────────────
              _slideCanvas(
                canvasDeck,
                settings,
                canvasSlide,
                idx,
                previewPage,
                hasRichTextPages,
              ),

              // ── Navigation footer ────────────────────────────────────────────
              _navFooter(
                l10n,
                deck,
                slide,
                idx,
                previewPage,
                pageCount,
                hasRichTextPages,
              ),

              // ── Theme chip ───────────────────────────────────────────────────
              _themeChip(l10n, deck),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(
    AppLocalizations l10n,
    Deck deck,
    int idx,
    int richTextPage,
    int richTextPages,
    bool hasRichTextPages,
  ) {
    return Container(
      color: AppTheme.paper,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.preview_outlined, size: 16, color: AppTheme.slate500),
          const SizedBox(width: 6),
          Text(
            l10n.d('Preview'),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: AppTheme.slate700,
            ),
          ),
          const Spacer(),
          // ── Zoom controls ──────────────────────────────────────
          Tooltip(
            message: l10n.d('Uitzoomen'),
            child: IconButton(
              icon: const Icon(Icons.remove, size: 16),
              onPressed: _zoom > _minZoom ? _zoomOut : null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              color: AppTheme.slate500,
            ),
          ),
          GestureDetector(
            onTap: _zoom != _minZoom ? _resetZoom : null,
            child: Tooltip(
              message: l10n.d('Zoom resetten'),
              child: Text(
                '${(_zoom * 100).round()}%',
                style: TextStyle(
                  fontSize: 11,
                  color: _zoom != _minZoom
                      ? AppTheme.accent
                      : AppTheme.slate400,
                  fontWeight: _zoom != _minZoom
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ),
          ),
          Tooltip(
            message: l10n.d('Inzoomen'),
            child: IconButton(
              icon: const Icon(Icons.add, size: 16),
              onPressed: _zoom < _maxZoom ? _zoomIn : null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              color: AppTheme.slate500,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            hasRichTextPages
                ? '${idx + 1} / ${deck.slides.length}'
                      ' · ${l10n.d('Pagina')} ${richTextPage + 1} / $richTextPages'
                : '${idx + 1} / ${deck.slides.length}',
            style: TextStyle(
              fontSize: 12,
              color: hasRichTextPages ? AppTheme.accent : AppTheme.slate400,
              fontWeight: hasRichTextPages
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: l10n.d('Preview inklappen'),
            child: IconButton(
              icon: const Icon(Icons.chevron_right, size: 18),
              onPressed: () =>
                  ref.read(previewCollapsedProvider.notifier).state = true,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              color: AppTheme.slate500,
            ),
          ),
        ],
      ),
    );
  }

  /// De balk die zegt wat er met deze dia gebeurt bij tonen en exporteren.
  ///
  /// Staat er altijd zolang de dia op "weglaten" staat, want dít is de stand die
  /// tot nu toe nergens te zien was: het label in de editor beloofde het, het
  /// scherm deed niets, en pas de PDF gaf antwoord. De melding noemt óók dat
  /// álle media van de dia verdwijnt — dat stond nergens, en het is de duurste
  /// verrassing van de twee: een dia die in de export ineens leeg is.
  ///
  /// De schakelaar ernaast is de controle. Uit toont hij de eigen tekst (anders
  /// valt er niets meer te bewerken), aan toont hij precies wat de ontvanger
  /// krijgt.
  ///
  /// "Wat de controle als persoonsgegeven aanmerkt" en niet "gevonden gegevens":
  /// een aanwijzing zonder persoon eromheen wordt wél gemeld maar niet gelakt
  /// (zie `PrivacyFinding.isRedactable`). De ruimere belofte zou de gebruiker
  /// laten denken dat het woord "diagnose" uit zijn export verdwijnt.
  Widget _redactionNotice(AppLocalizations l10n, bool showAudience) {
    return Container(
      width: double.infinity,
      color: AppTheme.warningBg,
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.visibility_off_outlined,
            size: 15,
            color: AppTheme.amber700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.d(
                'Weglaten staat aan: wat de controle als persoonsgegeven aanmerkt wordt zwart gemaakt, en álle afbeeldingen, video en audio van deze dia gaan niet mee naar het scherm of de export. Je markdown-bestand houdt alles.',
              ),
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                color: AppTheme.slate700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () =>
                ref.read(audiencePreviewProvider.notifier).update((on) => !on),
            icon: Icon(
              showAudience ? Icons.edit_outlined : Icons.groups_outlined,
              size: 15,
            ),
            label: Text(
              showAudience ? l10n.d('Mijn tekst') : l10n.d('Wat zij zien'),
              style: const TextStyle(fontSize: 11),
            ),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slideCanvas(
    Deck deck,
    AppSettings settings,
    Slide slide,
    int idx,
    int richTextPage,
    bool hasRichTextPages,
  ) {
    return Expanded(
      child: ClipRect(
        child: InteractiveViewer(
          transformationController: _transform,
          minScale: _minZoom,
          maxScale: _maxZoom,
          constrained: true,
          onInteractionUpdate: (details) {
            final scale = _transform.value.getMaxScaleOnAxis();
            if ((scale - _zoom).abs() > 0.01) {
              setState(() => _zoom = scale.clamp(_minZoom, _maxZoom));
            }
          },
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Container(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: SlidePreviewWidget(
                  slide: slide,
                  projectPath: deck.projectPath,
                  themeProfile: deck.themeProfile,
                  cockpitColorScheme: settings.cockpitColorScheme,
                  onLinkTap: openExternalUrl,
                  slideNumber: idx + 1,
                  slideCount: deck.slides.length,
                  numberStart: numberedListStartFor(deck.slides, idx),
                  scopeCia: deckScopeCiaIndex(deck.slides),
                  reportLanguage: deck.language,
                  fitScaleOverride: sharedSplitFitScale(
                    deck.slides,
                    idx,
                    deck.themeProfile,
                    deck.themeProfile.fontFamily,
                  ),
                  richTextPage: richTextPage,
                  showRichTextPageControls: hasRichTextPages,
                  onRichTextPageChanged: hasRichTextPages
                      ? (page) =>
                            ref
                                    .read(richTextPreviewPageProvider.notifier)
                                    .state =
                                page
                      : null,
                  tlp: deck.tlp,
                  organization: deck.organization,
                  deckSignature: deck.signature,
                  sealedAt: deck.finalized ? deck.sealAt : '',
                  showClassificationWatermark:
                      settings.classificationWatermarkEnabled,
                  // In de editor mag audio/video bediend worden, maar
                  // niet vanzelf starten (anders dreunt het door op
                  // elke slide-wissel).
                  enableMedia: true,
                  autoplayMedia: false,
                  allowRemoteMedia: settings.allowRemoteMedia,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navFooter(
    AppLocalizations l10n,
    Deck deck,
    Slide slide,
    int idx,
    int richTextPage,
    int richTextPages,
    bool hasRichTextPages,
  ) {
    return Container(
      color: AppTheme.paper,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: idx > 0 || richTextPage > 0 ? () => _move(-1) : null,
            icon: const Icon(Icons.chevron_left),
            iconSize: 20,
            tooltip: hasRichTextPages && richTextPage > 0
                ? l10n.d('Vorige pagina')
                : l10n.d('Vorige slide'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.d(slide.type.label),
                  style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                ),
                if (hasRichTextPages)
                  Text(
                    '${l10n.d('Pagina')} ${richTextPage + 1} / $richTextPages',
                    style: TextStyle(fontSize: 10, color: AppTheme.slate400),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed:
                idx < deck.slides.length - 1 ||
                    (hasRichTextPages && richTextPage < richTextPages - 1)
                ? () => _move(1)
                : null,
            icon: const Icon(Icons.chevron_right),
            iconSize: 20,
            tooltip: hasRichTextPages && richTextPage < richTextPages - 1
                ? l10n.d('Volgende pagina')
                : l10n.d('Volgende slide'),
          ),
        ],
      ),
    );
  }

  Widget _themeChip(AppLocalizations l10n, Deck deck) {
    return Container(
      color: AppTheme.slate50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.palette_outlined, size: 12, color: AppTheme.slate400),
          const SizedBox(width: 4),
          Text(
            '${l10n.d('Thema')}: ${deck.theme}',
            style: TextStyle(fontSize: 10, color: AppTheme.slate400),
          ),
          if (deck.paginate) ...[
            const SizedBox(width: 10),
            Icon(Icons.tag, size: 12, color: AppTheme.slate400),
            const SizedBox(width: 2),
            Text(
              l10n.d('paginering aan'),
              style: TextStyle(fontSize: 10, color: AppTheme.slate400),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Full-deck preview overlay ─────────────────────────────────────────────────

class FullDeckPreview extends ConsumerWidget {
  final Deck deck;
  final ThemeProfile themeProfile;

  const FullDeckPreview({
    super.key,
    required this.deck,
    required this.themeProfile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final showWatermark = ref
        .watch(settingsProvider)
        .classificationWatermarkEnabled;
    return Scaffold(
      backgroundColor: AppTheme.panelBg,
      appBar: AppBar(
        title: Text('${deck.title} — ${l10n.d('volledig deck')}'),
        backgroundColor: AppTheme.navy,
        leading: IconButton(
          tooltip: l10n.d('Sluiten'),
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 40),
        itemCount: deck.slides.length,
        itemBuilder: (_, i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${l10n.d('Slide')} ${i + 1}',
                  style: TextStyle(color: AppTheme.slate500, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Container(
                  decoration: const BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 12,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: SlidePreviewWidget(
                    slide: deck.slides[i],
                    projectPath: deck.projectPath,
                    themeProfile: themeProfile,
                    cockpitColorScheme: ref
                        .watch(settingsProvider)
                        .cockpitColorScheme,
                    allowRemoteMedia: ref
                        .watch(settingsProvider)
                        .allowRemoteMedia,
                    onLinkTap: openExternalUrl,
                    slideNumber: i + 1,
                    slideCount: deck.slides.length,
                    scopeCia: deckScopeCiaIndex(deck.slides),
                    reportLanguage: deck.language,
                    tlp: deck.tlp,
                    organization: deck.organization,
                    deckSignature: deck.signature,
                    sealedAt: deck.finalized ? deck.sealAt : '',
                    showClassificationWatermark: showWatermark,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Ingeklapt preview-paneel ──────────────────────────────────────────────────

/// Smal verticaal balkje dat het ingeklapte preview-paneel vervangt; klikken
/// klapt het weer uit.
class CollapsedPreviewBar extends ConsumerWidget {
  const CollapsedPreviewBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Container(
      width: 34,
      color: AppTheme.paper,
      child: Column(
        children: [
          const SizedBox(height: 6),
          Tooltip(
            message: l10n.d('Preview uitklappen'),
            child: IconButton(
              icon: const Icon(Icons.chevron_left, size: 18),
              onPressed: () =>
                  ref.read(previewCollapsedProvider.notifier).state = false,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              color: AppTheme.slate500,
            ),
          ),
          const SizedBox(height: 8),
          // Verticaal label "PREVIEW".
          RotatedBox(
            quarterTurns: 1,
            child: Text(
              context.l10n.d('PREVIEW'),
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.slate400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
