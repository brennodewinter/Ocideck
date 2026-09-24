import 'markdown_validation.dart';

/// De Marp-compatibiliteit van een deck-bron, zoals een gebruiker hem ziet.
///
/// - [compatible]: Marp rendert het deck zoals bedoeld — geen bevindingen
///   boven info-niveau.
/// - [degraded]: Marp rendert, maar iets degrageert (grafiek → codeblok,
///   skip-dia toont toch, onbekend thema zonder projectmap).
/// - [accepted]: er zijn warnings én het deck draagt
///   `ocideck_marp_compat_accepted` — de auteur heeft het verlies bewust
///   geaccepteerd. Eigen status (niet groen): geaccepteerd is niet hetzelfde
///   als schoon.
/// - [incompatible]: Marp faalt of rendert geen slides (`marp: true`
///   ontbreekt, kapotte front matter). Altijd boven geaccepteerd: fouten zijn
///   niet acceptabel.
enum MarpCompatStatus { compatible, degraded, accepted, incompatible }

/// Waar het bestand heen gaat — bepaalt welke warnings logisch zijn.
///
/// [project]: de schrijver legt `.marprc.yml`/`themes/`/`images/` naast de
/// `.md` (desktop-opslag in een projectmap), dus een custom thema en
/// relatieve media werken. [bareFile]: een los `.md`-bestand (web-download,
/// remote flat save) waar alles in de tekst zelf moet kloppen.
enum MarpCompatContext { project, bareFile }

/// Uitkomst van [MarpCompatibility.check]: de status plus de losse
/// bevindingen (zelfde model als de structuurcontrole, zodat de bestaande
/// issue-lijst-UI er direct mee overweg kan).
class MarpCompatReport {
  final MarpCompatStatus status;
  final List<MarkdownValidationIssue> findings;

  /// Of de bron `ocideck_marp_compat_accepted: true` draagt. Blijft ook zichtbaar
  /// als er (nog) geen warnings zijn — de vlag is een deck-eigenschap, geen
  /// bevindingseigenschap.
  final bool accepted;

  const MarpCompatReport({
    required this.status,
    required this.findings,
    this.accepted = false,
  });

  int get errorCount => findings
      .where((f) => f.severity == MarkdownValidationSeverity.error)
      .length;

  int get warningCount => findings
      .where((f) => f.severity == MarkdownValidationSeverity.warning)
      .length;
}
