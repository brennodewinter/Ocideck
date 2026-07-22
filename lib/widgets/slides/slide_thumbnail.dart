import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/cvss_builder.dart';
import '../../models/deck.dart';
import '../../models/privacy_disposition.dart';
import '../../models/quality_disposition.dart';
import '../../models/slide_quality.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../state/deck_provider.dart';
import '../../state/deck_quality_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/image_contrast_provider.dart';
import '../../state/image_privacy_provider.dart';
import '../../state/privacy_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/slide_clipboard_provider.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../privacy_badge.dart' show privacyKatSvg;
import 'slide_badge_popover.dart';
import 'slide_badge_tone.dart';
import 'slide_preview.dart';

String _qualityBadgeTooltip(AppLocalizations l10n, SlideBadgeTone tone) =>
    switch (tone) {
      SlideBadgeTone.error => l10n.d(
        'Kwaliteitsproblemen (inclusief ernstige)',
      ),
      SlideBadgeTone.accepted => l10n.d('Kwaliteitsproblemen geaccepteerd'),
      _ => l10n.d('Kwaliteitsproblemen'),
    };

/// Waarom deze dia het publiek niet haalt terwijl de auteur hem niet oversloeg.
/// Noemt het niveau erbij: zonder dat cijfer weet je wel *dát* hij wegvalt maar
/// niet welke knop je moet omzetten.
String _withheldTooltip(AppLocalizations l10n, TlpLevel slideTlp) =>
    '${l10n.d('Achtergehouden: strenger geclassificeerd dan de presentatie')} '
    '(${slideTlp.label})';

String _privacyBadgeTooltip(AppLocalizations l10n, SlideBadgeTone tone) =>
    switch (tone) {
      SlideBadgeTone.hint => l10n.d('Mogelijk persoonsgegevens'),
      SlideBadgeTone.accepted => l10n.d('Persoonsgegevens geaccepteerd'),
      _ => l10n.d('Persoonsgegevens gevonden'),
    };

/// Het badge-plaatje zelf: een gekleurd blokje met een icoon, dat antwoord geeft.
///
/// Twee gebaren, en het onderscheid ertussen is de hele afspraak:
///
///   * **enkele klik** opent het lijstje meldingen. Dat is de veilige actie, en
///     dus de makkelijkste;
///   * **dubbelklik** beslist. Op een gekleurde badge accepteer je wat er staat,
///     op een grijze draai je die acceptatie terug.
///
/// Dat dubbelklikken twee kanten op werkt is geen symmetrie om de symmetrie: een
/// beslissing die je niet met hetzelfde gebaar kunt terugnemen, durf je niet te
/// nemen.
class _SlideBadge extends ConsumerStatefulWidget {
  final SlideBadgeTone tone;
  final String message;
  final int slideIndex;
  final SlideBadgeFamily family;
  final Widget child;

  const _SlideBadge({
    required this.tone,
    required this.message,
    required this.slideIndex,
    required this.family,
    required this.child,
  });

  @override
  ConsumerState<_SlideBadge> createState() => _SlideBadgeState();
}

class _SlideBadgeState extends ConsumerState<_SlideBadge> {
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.message,
      child: GestureDetector(
        // Vangt de tik af vóór de kaart eronder: klikken op de badge hoort de
        // meldingen te openen, niet alleen de slide te selecteren.
        behavior: HitTestBehavior.opaque,
        onTap: () => showSlideBadgeFindings(
          context: context,
          ref: ref,
          slideIndex: widget.slideIndex,
          family: widget.family,
          tone: widget.tone,
        ),
        onDoubleTap: () =>
            toggleSlideBadgeAcceptance(ref, widget.slideIndex, widget.family),
        child: Tooltip(
          message: widget.message,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: widget.tone.background,
              borderRadius: BorderRadius.circular(4),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class SlideThumbnail extends ConsumerWidget {
  final Slide slide;
  final int index;
  final String? projectPath;
  final ThemeProfile themeProfile;
  final int slideCount;
  final TlpLevel tlp;
  final String organization;
  final VoidCallback onTap;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onToggleSkip;
  final VoidCallback onCopyImage;
  final VoidCallback onSplit;

  /// Persoonlijke gebruikersnotities (sidecar), los van sprekersnotities.
  final bool hasUserNotes;

  /// Shared font scale when this slide is one page of a split run, so the rail
  /// matches the main preview (see [SlidePreviewWidget.fitScaleOverride]).
  final double? fitScaleOverride;

  /// First number a continued numbered list shows here, so the rail matches the
  /// main preview and the presentation (see [SlidePreviewWidget.numberStart]).
  final int numberStart;

  /// Deck scope-object → CIA-rating index, so a finding thumbnail's severity
  /// colour matches the main preview (see [SlidePreviewWidget.scopeCia]).
  final Map<String, CiaRating> scopeCia;

  /// The report's language (see [SlidePreviewWidget.reportLanguage]), so a
  /// thumbnail reads the same as the slide it stands for.
  final String reportLanguage;

  const SlideThumbnail({
    super.key,
    required this.slide,
    required this.index,
    required this.onTap,
    required this.onDuplicate,
    required this.onDelete,
    required this.onToggleSkip,
    required this.onCopyImage,
    required this.onSplit,
    this.hasUserNotes = false,
    this.projectPath,
    this.themeProfile = const ThemeProfile(),
    this.slideCount = 1,
    this.tlp = TlpLevel.none,
    this.organization = '',
    this.fitScaleOverride,
    this.numberStart = 1,
    this.scopeCia = const {},
    this.reportLanguage = '',
  });

  /// De twee badge-tonen van deze kaart: kwaliteit en privacy.
  ///
  /// Twee badges, geen één. Privacy zat ooit in de kwaliteitsbadge gevouwen, en
  /// dat maakte het bolletje onleesbaar: het kon contrast betekenen, of
  /// tekstdichtheid, of een BSN in de tekst. Wie een deck nakeek op
  /// persoonsgegevens kon niet zien wélke dia's daarover gingen — en wie een
  /// contrastwaarschuwing zag, kon denken dat er persoonsgegevens stonden.
  ///
  /// Elke toon leest de RUWE uitslagen (tekst, beeld én — voor privacy — de
  /// gezichtsscan, voor kwaliteit óók de asynchrone titel-over-beeld-contrast).
  /// Ruw, zodat een afgehandelde melding grijs blijft in plaats van te
  /// verdwijnen: verdween ze, dan zag een dia waarvan de auteur de bevinding
  /// bewust accepteerde er precies zo uit als een dia waarop niets gevonden is.
  /// En omdat badge én popover uit dezelfde ruwe uitslagen lezen, kan het
  /// overzicht nooit iets tonen dat de badge bij aanklikken ontkent.
  ///
  /// Selects op kleine waarden i.p.v. het hele resultaat: anders herbouwt élke
  /// thumbnail bij elke wijziging waar dan ook in het deck.
  (SlideBadgeTone, SlideBadgeTone) _badgeTones(WidgetRef ref) {
    final privacyDone = ref.watch(
      deckProvider.select(
        (state) => effectivePrivacyDisposition(
          deck: state.deck?.privacy ?? PrivacyDisposition.warn,
          slide: slide.privacy,
        ).isResolved,
      ),
    );
    final qualityAccepted = slide.quality.isResolved;
    final syncQualityTone = ref.watch(
      deckQualityRawProvider.select(
        (r) => qualityBadgeTone(r.forSlide(index), accepted: qualityAccepted),
      ),
    );
    final imageContrastTone = ref.watch(
      imageContrastIssuesProvider.select(
        (async) => qualityBadgeTone(
          (async.value ?? const <SlideQualityIssue>[]).where(
            (i) => i.slideIndex == index,
          ),
          accepted: qualityAccepted,
        ),
      ),
    );
    final textPrivacyTone = ref.watch(
      privacyRawScanProvider.select(
        (scan) => privacyBadgeTone(scan.forSlide(index), accepted: privacyDone),
      ),
    );
    final imagePrivacyTone = ref.watch(
      imagePrivacyRawIssuesProvider.select(
        (async) =>
            (async.value ?? const <SlideQualityIssue>[]).any(
              (i) => i.slideIndex == index,
            )
            ? (privacyDone ? SlideBadgeTone.accepted : SlideBadgeTone.warning)
            : SlideBadgeTone.none,
      ),
    );
    return (
      worstBadgeTone(syncQualityTone, imageContrastTone),
      worstBadgeTone(textPrivacyTone, imagePrivacyTone),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final skipped = slide.skipped;
    // Achtergehouden door TLP: dezelfde zichtbare behandeling als overslaan —
    // gedimd, met een eigen badge — want het gevolg is hetzelfde (de dia haalt
    // presentatie, export én pakket niet). Wel een eigen woord en een eigen
    // kleur: de oorzaak is een andere en de uitweg dus ook.
    final withheld = slideWithheldByTlp(slide, tlp);
    // Elke thumbnail bewaakt alléén zijn eigen selectiestatus. Zo rebuildt bij
    // een selectiewissel alleen de oude en de nieuwe kaart, niet de hele lijst.
    // (isSelected = onderdeel van de selectie; isPrimary = de actieve slide.)
    final (isSelected, isPrimary) = ref.watch(
      editorProvider.select(
        (s) => (s.selection.contains(index), s.selectedIndex == index),
      ),
    );
    final (qualityTone, privacyTone) = _badgeTones(ref);
    final showWatermark = ref.watch(
      settingsProvider.select((s) => s.classificationWatermarkEnabled),
    );
    // "In tweeën splitsen" is beschikbaar op elke bulletslide met genoeg bullets
    // om te verdelen — óók bullets-met-afbeelding, waar het tekstvlak maar de
    // halve breedte heeft en een slide dus eerder vol oogt dan de algemene
    // bullettelling-drempel suggereert. De daadwerkelijke knip (op het optimum
    // dat past) gebeurt in DeckNotifier.splitSlide.
    // Dezelfde toets als de knop in het paneel: één [canSplitSlide], niet een
    // eigen kopie met een `_ => false` die een nieuw bullettype hier stil
    // onsplitsbaar zou maken.
    final canSplit = canSplitSlide(slide);
    final borderColor = isSelected
        ? AppTheme.accent
        : withheld
        ? AppTheme.badgeErrorOverlay
        : skipped
        ? AppTheme.goldDark
        : AppTheme.darkSlate600;
    // Actieve slide krijgt een dikkere rand dan de overige geselecteerde.
    final borderWidth = isSelected ? (isPrimary ? 2.5 : 1.6) : 1.0;

    // Eén beknopt label per kaart voor schermlezers: nummer, titel (of type)
    // en status. De mini-preview eronder is puur visueel en zou anders de
    // volledige slide-inhoud per thumbnail laten voorlezen.
    final title = slide.title.trim();
    final semanticLabel =
        '${l10n.d('Slide')} ${index + 1}/$slideCount: '
        '${title.isNotEmpty ? title : l10n.d(slide.type.label)}'
        '${skipped ? ' (${l10n.d('Overgeslagen')})' : ''}'
        '${withheld ? ' (${_withheldTooltip(l10n, slide.tlp)})' : ''}'
        '${hasUserNotes ? ' (${l10n.d('Gebruikersnotities')})' : ''}'
        // Twee badges, dus twee mededelingen. Ze samenvatten als één
        // "Kwaliteitsprobleem" zou een schermlezergebruiker precies de vraag
        // laten staan die de badges nu net beantwoorden: wélk soort probleem.
        '${qualityTone.isVisible ? ' (${_qualityBadgeTooltip(l10n, qualityTone)})' : ''}'
        '${privacyTone.isVisible ? ' (${_privacyBadgeTooltip(l10n, privacyTone)})' : ''}';

    return Semantics(
      button: true,
      selected: isSelected,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor, width: borderWidth),
            color: isSelected ? AppTheme.darkSlate700 : AppTheme.darkSlate800,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Mini slide preview
              _miniPreview(
                ref,
                l10n,
                skipped: skipped,
                withheld: withheld,
                showWatermark: showWatermark,
                qualityTone: qualityTone,
                privacyTone: privacyTone,
              ),
              // Footer: slide number, type label, action buttons
              _footer(
                ref,
                l10n,
                skipped: skipped,
                canSplit: canSplit,
                isSelected: isSelected,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Het vlaggetje linksboven op de mini-preview: icoon plus woord, want een
  /// icoon alleen laat de gebruiker raden waaróm deze dia er straks niet is.
  Widget _cornerBadge({
    required Color color,
    required IconData icon,
    required String label,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: Colors.white),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _miniPreview(
    WidgetRef ref,
    AppLocalizations l10n, {
    required bool skipped,
    required bool withheld,
    required bool showWatermark,
    required SlideBadgeTone qualityTone,
    required SlideBadgeTone privacyTone,
  }) {
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Overgeslagen slides worden gedimd weergegeven. De preview is de
              // dure verf (thumbnail-raster); een RepaintBoundary isoleert hem
              // zodat een naburige kaart die verandert deze niet mee herverft.
              Opacity(
                opacity: skipped || withheld ? 0.32 : 1,
                child: RepaintBoundary(
                  child: SlidePreviewWidget(
                    slide: slide,
                    projectPath: projectPath,
                    themeProfile: themeProfile,
                    // Een thumbnail is ~180 px breed; op ware grootte
                    // decoderen kost per telefoonfoto bijna 49 MiB, en tien
                    // zichtbare stroken met verschillende foto's zijn een halve
                    // gigabyte aan levende bitmaps (#612). 512 houdt hem scherp
                    // op een hidpi-scherm en kost een dertigste.
                    decodeMaxEdge: 512,
                    cockpitColorScheme: ref.watch(
                      settingsProvider.select((s) => s.cockpitColorScheme),
                    ),
                    allowRemoteMedia: ref.watch(
                      settingsProvider.select((s) => s.allowRemoteMedia),
                    ),
                    slideNumber: index + 1,
                    slideCount: slideCount,
                    numberStart: numberStart,
                    scopeCia: scopeCia,
                    reportLanguage: reportLanguage,
                    fitScaleOverride: fitScaleOverride,
                    tlp: tlp,
                    organization: organization,
                    showClassificationWatermark: showWatermark,
                  ),
                ),
              ),
              // Onder elkaar en niet naast elkaar: een dia kán allebei zijn
              // (overgeslagen én te streng geclassificeerd), en dan moeten de
              // twee redenen los leesbaar blijven.
              if (skipped || withheld)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (skipped)
                        _cornerBadge(
                          color: AppTheme.goldDarkOverlay,
                          icon: Icons.visibility_off_outlined,
                          label: l10n.d('Overgeslagen'),
                        ),
                      if (skipped && withheld) const SizedBox(height: 3),
                      if (withheld)
                        Tooltip(
                          message: _withheldTooltip(l10n, slide.tlp),
                          child: _cornerBadge(
                            color: AppTheme.badgeErrorOverlay,
                            icon: Icons.lock_outline,
                            label: l10n.d('Achtergehouden'),
                          ),
                        ),
                    ],
                  ),
                ),
              if (hasUserNotes)
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: Tooltip(
                    message: l10n.d('Gebruikersnotities'),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: AppTheme.accentOverlay,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.edit_note_outlined,
                        size: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              // Rechtsboven de twee badges naast elkaar, kwaliteit eerst.
              // Naast elkaar en niet gestapeld: de thumbnail is klein, en twee
              // markeringen boven elkaar in dezelfde hoek lezen als één brede.
              if (qualityTone.isVisible || privacyTone.isVisible)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (qualityTone.isVisible)
                        _SlideBadge(
                          tone: qualityTone,
                          message: _qualityBadgeTooltip(l10n, qualityTone),
                          slideIndex: index,
                          family: SlideBadgeFamily.quality,
                          child: Icon(
                            Icons.accessibility_new_outlined,
                            size: 10,
                            color: qualityTone.foreground,
                          ),
                        ),
                      if (qualityTone.isVisible && privacyTone.isVisible)
                        const SizedBox(width: 3),
                      if (privacyTone.isVisible)
                        _SlideBadge(
                          tone: privacyTone,
                          message: _privacyBadgeTooltip(l10n, privacyTone),
                          slideIndex: index,
                          family: SlideBadgeFamily.privacy,
                          child: SvgPicture.string(
                            privacyKatSvg,
                            width: 10,
                            height: 10,
                            colorFilter: ColorFilter.mode(
                              privacyTone.foreground,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer(
    WidgetRef ref,
    AppLocalizations l10n, {
    required bool skipped,
    required bool canSplit,
    required bool isSelected,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.accent : AppTheme.darkSlate500,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              l10n.d(slide.type.label),
              style: TextStyle(color: AppTheme.slate400, fontSize: 9),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Drag handle
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 2),
              child: Icon(
                Icons.drag_handle,
                size: 14,
                color: AppTheme.slate500,
              ),
            ),
          ),
          // Snelle overslaan-toggle
          SizedBox(
            width: 20,
            height: 20,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 14,
              splashRadius: 12,
              tooltip: skipped
                  ? l10n.d('Weer tonen bij presenteren/exporteren')
                  : l10n.d('Overslaan bij presenteren/exporteren'),
              icon: Icon(
                skipped ? Icons.visibility_off : Icons.visibility_outlined,
                color: skipped ? AppTheme.gold : AppTheme.slate500,
              ),
              onPressed: onToggleSkip,
            ),
          ),
          // Context menu
          SizedBox(
            width: 20,
            height: 20,
            child: PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: AppTheme.slate500, size: 14),
              padding: EdgeInsets.zero,
              itemBuilder: (_) => [
                PopupMenuItem(value: 'copy', child: Text(l10n.d('Kopiëren'))),
                PopupMenuItem(
                  value: 'copy_image',
                  child: Text(l10n.d('Kopieer als afbeelding')),
                ),
                PopupMenuItem(
                  value: 'duplicate',
                  child: Text(l10n.d('Dupliceren')),
                ),
                if (canSplit)
                  PopupMenuItem(
                    value: 'split',
                    child: Text(l10n.d('In tweeën splitsen')),
                  ),
                PopupMenuItem(
                  value: 'skip',
                  child: Text(
                    skipped
                        ? l10n.d('Niet meer overslaan')
                        : l10n.d('Overslaan'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    l10n.d('Verwijderen'),
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
              onSelected: (v) {
                if (v == 'copy') {
                  ref.read(slideClipboardProvider.notifier).state = slide;
                }
                if (v == 'copy_image') onCopyImage();
                if (v == 'duplicate') onDuplicate();
                if (v == 'split') onSplit();
                if (v == 'skip') onToggleSkip();
                if (v == 'delete') onDelete();
              },
            ),
          ),
        ],
      ),
    );
  }
}
