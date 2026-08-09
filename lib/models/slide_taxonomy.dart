part of 'slide.dart';

/// Broad grouping a [SlideType] belongs to, used by the add-slide picker to
/// offer category tabs. The picker derives its tabs from the categories that
/// are actually present.
enum SlideCategory {
  general,
  informationSecurity,
  procesverbetering,
  managementsysteem,
}

/// Hoeveel kolommen doorlopende bullettekst een [SlideType] toont.
enum BulletColumns { none, one, two }

/// The part a slide plays inside a finding group.
enum FindingRole { header, detail, evidence }

enum ListStyle { bullets, numbered, checklist, richText }

/// Native Marp image-column layout for a title slide (#1405).
enum TitleColumnLayout { none, left, right, both }

/// Per-kolomuitlijning uit de GFM-scheidingsrij van een tabel.
enum TableAlign { left, center, right }
