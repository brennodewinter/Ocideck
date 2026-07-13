import '../models/checklist_spec.dart';
import '../models/checklist_template.dart';
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

/// A source built from a user-created [template].
ChecklistSource templateChecklistSource(ChecklistTemplate template) =>
    ChecklistSource(
      label: template.name,
      standardLabel: template.standardLabel,
      rows: [
        for (final i in template.items) ChecklistRow(id: i.id, test: i.title),
      ],
    );

/// Every available source: WSTG first, then the user's [custom] templates.
List<ChecklistSource> checklistSources(List<ChecklistTemplate> custom) => [
  wstgChecklistSource(),
  for (final t in custom) templateChecklistSource(t),
];
