// Alles wat een export nodig heeft, voor één doelgroepprofiel.
//
// Dit bestaat om een spanning op te lossen die anders niet op te lossen was. De
// gebruiker moet in het exportdialoog kunnen kiezen vóór wie de export bedoeld is
// — de opdrachtgever krijgt alles, de bredere kring krijgt het geredigeerde
// exemplaar. Maar het dialoog mág de bron niet hebben: dat is de hele
// projectiegrens (`PrivacyProjection`).
//
// De oplossing is een fabriek. Het dialoog krijgt een functie die per profiel een
// bundel oplevert, en die functie sluit in de shell om de bron heen. Het dialoog
// kan er dus alleen `AudienceDeck`s uit halen — nooit het origineel — en de grens
// blijft staan terwijl de keuze toch in het dialoog ligt.

import '../models/deck.dart';
import '../models/redaction_manifest.dart';
import '../models/slide.dart';
import 'finding_pagination.dart';
import 'markdown_service.dart';
import '../models/privacy_disposition.dart';
import 'privacy/privacy_export_policy.dart';
import 'privacy/privacy_own_identity.dart';
import 'privacy/privacy_projection.dart';
import 'privacy/privacy_scanner.dart';
import 'privacy/redaction_manifest_service.dart';
import 'rich_text_layout.dart';

/// Eén doelgroepprofiel, uitgewerkt.
class ExportBundle {
  /// Het geprojecteerde deck: pixels, notities, metadata.
  final AudienceDeck audience;

  /// De markdown voor de HTML-export. Uit hetzelfde geprojecteerde deck — de
  /// HTML zet de markdown letterlijk in het bestand.
  final String markdown;

  /// Het redactiemanifest van dít profiel. Bevat de salts; het exemplaar dat
  /// meereist met het geredigeerde rapport is `manifest.withoutSalts`.
  final RedactionManifest manifest;

  /// Wat er in het deck zit, geteld naar wat de auteur ermee heeft gedaan.
  final PrivacyExportSummary privacySummary;

  const ExportBundle({
    required this.audience,
    required this.markdown,
    required this.manifest,
    required this.privacySummary,
  });
}

/// Wat de export daadwerkelijk opsomt: dezelfde slides, maar met alles wat op
/// het scherm één slide is en op papier meerdere pagina's, uitgeklapt.
///
/// Een overlopende bevinding wordt zo geëxporteerd als een paar dia's op ware
/// grootte in plaats van één ineengekrompen dia. Voor een lange vrije-
/// tekstslide gold hetzelfde probleem omgekeerd: de editor en de presentator
/// bladeren door zijn pagina's, maar de export somt op — hij rasterde pagina 1
/// en de rest verdween geruisloos uit het bestand. Beide uitklappen laten het
/// deck zelf ongemoeid, en omdat de voettekst zijn nummer uit de positie in
/// deze lijst haalt, telt hij de pagina's nu vanzelf mee.
List<Slide> _expandForExport(List<Slide> slides, Deck deck) =>
    expandRichTextForRender(expandFindingsForRender(slides), deck.themeProfile);

/// Eén exportbundel: het geprojecteerde deck plus alles wat daaruit volgt.
///
/// Hoort hier en niet in de shell: dit is exportlogica, geen schermlogica. De
/// aanroeper geeft de bron mee; wat hij terugkrijgt is de projectie ervan, en
/// dat is precies de grens die de kop van dit bestand beschrijft.
ExportBundle buildExportBundle(
  Deck deck,
  List<Slide> slides, {
  required PrivacyExportProfile profile,
  required bool includeDetail,
  required Set<String> disabledRules,
  required OwnIdentity ownIdentity,
  required Set<String> regions,
  required MarkdownService markdownService,
}) {
  // De beknopte versie laat de verdiepingsslides weg. Filteren gebeurt vóór
  // de paginering: een overlopende bevinding die in drie slides uiteenvalt
  // erft zijn verdiepingsvlag, en die drie horen samen te blijven.
  final chosen = includeDetail
      ? slides
      : slides.where((s) => !s.isDetail).toList();

  // De projectiegrens. Vanaf hier raakt geen enkel exportpad de bron nog aan:
  // de rasterizer, de markdown voor de HTML-export, de PPTX-notities en de
  // documentmetadata worden allemaal uit dit ene object afgeleid.
  final source = deck.copyWith(slides: _expandForExport(chosen, deck));

  // Eén scan voor de hele bundel; het waren er drie, één per afnemer hieronder,
  // alle drie over hetzelfde deck (#613).
  final scan = PrivacyScanner(
    disabledRules: disabledRules,
    ownIdentity: ownIdentity,
    regions: regions,
  ).scan(source);

  final audience = PrivacyProjection.forAudience(
    source,
    disabledRules: disabledRules,
    ownIdentity: ownIdentity,
    regions: regions,
    profile: profile,
    scan: scan,
  );
  return ExportBundle(
    audience: audience,
    // Inline chart data so the HTML export can render charts standalone, even
    // when a chart links an external CSV. Gegenereerd uit het geprojecteerde
    // deck: de HTML-export zet deze markdown letterlijk in het bestand.
    markdown: markdownService.generateDeck(
      audience.deck,
      inlineChartData: true,
      forExport: true,
    ),
    manifest: RedactionManifestService(
      disabledRules: disabledRules,
      ownIdentity: ownIdentity,
      regions: regions,
    ).build(source, profile: profile, scan: scan),
    // De gate telt op de ONGEFILTERDE scan: de provider onderdrukt bevindingen
    // op slides die de auteur al heeft afgehandeld — precies wat je in het
    // paneel wilt, en precies wat je in deze samenvatting niet wilt.
    privacySummary: summarisePrivacyForExport(source, scan),
  );
}
