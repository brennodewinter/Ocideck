/// The managementsysteem-module models (ISO_MANAGEMENTSYSTEEM design doc §1/§7):
/// the three supported management-system standards and the *index* of their
/// clauses/controls. This is the "eigen organisatie"-blik — one management
/// system per deck — not a per-client scope like the pentest module.
///
/// Only the **index** lives here: clause/control number + short canonical
/// title + section. The normative requirement text is copyrighted and is **not**
/// bundled (see the licence note in `management_system_catalog.dart` and design
/// doc §9). These types stay Flutter-free; the UI localises its own chrome and
/// shows the (English, canonical) titles as data, exactly as the WSTG/CWE
/// catalogs do with their titles.
library;

/// Which management-system standard a deck reports against. The [token] is the
/// stable, language-independent word stored in the deck's front matter
/// (`ocideck_ms_standard`), so a deck round-trips regardless of interface
/// language — the same convention as [ChecklistStatus.token].
enum ManagementSystemStandard {
  /// ISO/IEC 27001 — Information security management system (ISMS). Reports
  /// against the Annex A controls (2022 edition: 93 controls in four themes).
  iso27001('iso27001', 'ISO/IEC 27001', '2022', hasAnnexA: true),

  /// ISO 9001 — Quality management system (QMS). Clause-based: there is no
  /// Annex A, so progress is reported against clauses 4–10 and their
  /// sub-clauses.
  iso9001('iso9001', 'ISO 9001', '2015', hasAnnexA: false),

  /// ISO/IEC 42001 — Artificial intelligence management system (AIMS). Reports
  /// against the Annex A controls (2023 edition: 38 controls under objectives
  /// A.2–A.10).
  iso42001('iso42001', 'ISO/IEC 42001', '2023', hasAnnexA: true);

  const ManagementSystemStandard(
    this.token,
    this.name,
    this.edition, {
    required this.hasAnnexA,
  });

  /// The stable front-matter token (`iso27001` / `iso9001` / `iso42001`).
  final String token;

  /// The standard's name as a reader knows it, e.g. `ISO/IEC 27001`. Bundled
  /// reference data, not localised UI — like [ReferenceStandard.name].
  final String name;

  /// The bundled edition year the index reflects, e.g. `2022`. Kept in step with
  /// the `ReferenceStandard.bundledVersion` in `reference_standards.dart` so the
  /// freshness gate and this module never disagree on which edition is meant.
  final String edition;

  /// Whether the standard carries Annex A controls (27001, 42001) or is purely
  /// clause-based (9001). Drives whether the importer offers "Annex A" sources.
  final bool hasAnnexA;

  /// The name with its edition, as it belongs at the top of a report or in the
  /// standards-used overview, e.g. `ISO/IEC 27001:2022`.
  String get label => '$name:$edition';

  /// Maps a stored front-matter token back to a standard, or null when the token
  /// is unknown (a hand-edited or future value) so a deck never throws.
  static ManagementSystemStandard? fromToken(String value) {
    final v = value.trim().toLowerCase();
    for (final s in values) {
      if (s.token == v) return s;
    }
    return null;
  }
}

/// One section of a standard's index: an Annex A theme/objective (`A.5`,
/// `A.6`, … for 27001; `A.2`, `A.3`, … for 42001) or a top-level clause (`4`,
/// `5`, … for the clause-based 9001 tree). The [title] is the canonical English
/// heading — bundled data.
class ControlSection {
  const ControlSection({required this.id, required this.title});

  /// The stable section id, e.g. `A.5` or `4`.
  final String id;

  /// The canonical English heading, e.g. `Organizational controls` or
  /// `Context of the organization`.
  final String title;
}

/// One clause or control in a standard's index: its number, its short canonical
/// title, and the [sectionId] it belongs to. This is the row an importer turns
/// into a `controlStatus` row (id + control), with the status/owner/… left blank
/// for the author to fill in.
class ControlEntry {
  const ControlEntry({
    required this.id,
    required this.title,
    required this.sectionId,
  });

  /// The clause/control number, e.g. `A.5.1`, `A.6.2.4` or `9.3`. The stable key
  /// the progress overview joins on.
  final String id;

  /// The short canonical English title, e.g. `Policies for information
  /// security`. Bundled reference data (an index fact), not localised UI.
  final String title;

  /// The [ControlSection.id] this entry sits under.
  final String sectionId;
}
