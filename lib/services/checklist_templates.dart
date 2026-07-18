import '../models/checklist_spec.dart';
import '../models/checklist_template.dart';
import 'mastg_catalog.dart';
import 'wstg_catalog.dart';

/// A loadable set of checklist rows presented uniformly in the "load tests"
/// affordances (feedback #9): the bundled OWASP WSTG list and every user-created
/// [ChecklistTemplate] flow through the same shape, so the checklist editor and
/// the per-scope generation can append either without special-casing.
class ChecklistSource {
  const ChecklistSource({
    required this.label,
    required this.standardLabel,
    required this.rows,
  });

  /// The name shown in the picker.
  final String label;

  /// The standard label to put on the checklist slide when it has none yet.
  final String standardLabel;

  /// The rows to append (id + test; status/finding/note start blank).
  final List<ChecklistRow> rows;
}

/// The built-in OWASP WSTG source.
ChecklistSource wstgChecklistSource() => ChecklistSource(
  label: WstgCatalog.instance.standardLabel,
  standardLabel: WstgCatalog.instance.standardLabel,
  rows: [
    for (final t in WstgCatalog.instance.tests)
      ChecklistRow(id: t.id, test: t.title),
  ],
);

/// De ingebouwde OWASP MASTG-bronnen, één per platform.
///
/// Bewust gesplitst en niet één lijst van 186: een mobiele pentest raakt zelden
/// beide platforms, en een checklist waarvan de helft niet van toepassing is
/// wordt niet afgewerkt maar weggeklikt. Het etiket noemt het platform, zodat
/// op de slide te zien blijft welke helft is gebruikt.
ChecklistSource mastgChecklistSource(String platform) {
  final label = platform == 'ios' ? 'iOS' : 'Android';
  return ChecklistSource(
    label: '${MastgCatalog.instance.standardLabel} — $label',
    standardLabel: MastgCatalog.instance.standardLabel,
    rows: [
      for (final t in MastgCatalog.instance.forPlatform(platform))
        ChecklistRow(id: t.id, test: t.title),
    ],
  );
}

/// A source built from a user-created [template].
ChecklistSource templateChecklistSource(ChecklistTemplate template) =>
    ChecklistSource(
      label: template.name,
      standardLabel: template.standardLabel,
      rows: [
        for (final i in template.items) ChecklistRow(id: i.id, test: i.title),
      ],
    );

/// Every available source: the bundled standards first, then the user's
/// [custom] templates.
List<ChecklistSource> checklistSources(List<ChecklistTemplate> custom) => [
  wstgChecklistSource(),
  mastgChecklistSource('android'),
  mastgChecklistSource('ios'),
  for (final t in custom) templateChecklistSource(t),
];
