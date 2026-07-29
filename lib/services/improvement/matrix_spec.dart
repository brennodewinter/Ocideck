// Matrix engine data shapes for Procesverbetering (PROCESS_IMPROVEMENT.md §3.1).
// Pure Dart — derived columns (e.g. RPN) are never stored; callers compute them.
// Template *data* lives in assets/improvement/templates/ (see catalog).
library;

import 'improvement_template_catalog.dart';

/// A typed grid artefact (SIPOC, FMEA, RACI, …) rendered by the matrix engine.
class MatrixSpec {
  const MatrixSpec({
    required this.templateId,
    required this.columns,
    required this.rows,
    this.layout = MatrixLayout.grid,
  });

  /// Template id from assets/improvement (e.g. `sipoc`, `fmea`).
  final String templateId;

  final List<MatrixColumn> columns;
  final List<List<String>> rows;
  final MatrixLayout layout;

  /// Derive RPN = S×O×D when the column keys severity/occurrence/detection
  /// exist. Returns null when any factor is missing or not an int 1–10.
  static int? derivedRpn(List<String> row, List<MatrixColumn> columns) {
    int? read(String key) {
      final i = columns.indexWhere((c) => c.key == key);
      if (i < 0 || i >= row.length) return null;
      return int.tryParse(row[i].trim());
    }

    final s = read('severity') ?? read('s');
    final o = read('occurrence') ?? read('o');
    final d = read('detection') ?? read('d');
    if (s == null || o == null || d == null) return null;
    if (s < 1 || s > 10 || o < 1 || o > 10 || d < 1 || d > 10) return null;
    return s * o * d;
  }
}

enum MatrixLayout { grid, hoq }

/// The template a fresh `matrix` slide starts from. SIPOC is the Define-phase
/// opener, so it is the one an author is most likely to want first.
const String kDefaultImprovementTemplateId = 'sipoc';

/// Bundled matrix templates from [ImprovementTemplateCatalog].
List<ImprovementTemplate> get bundledImprovementTemplates =>
    ImprovementTemplateCatalog.instance.matrixTemplates;

/// The bundled template with [id], or null when nothing carries it.
///
/// Een onbekende id is geen fout: een deck kan uit een nieuwere versie of uit
/// iemands eigen sjabloonpakket komen. De aanroeper valt dan terug op de
/// opgeslagen tabelkop.
ImprovementTemplate? improvementTemplateById(String id) =>
    ImprovementTemplateCatalog.instance.matrixById(id);

/// The table rows a fresh slide of template [id] starts with: the header row
/// plus [dataRows] empty rows. Unknown ids yield a bare two-column grid, so a
/// caller never has to special-case "template gone".
List<List<String>> improvementTemplateStarterRows(
  String id, {
  int dataRows = 1,
}) {
  final template = improvementTemplateById(id);
  final header = template == null
      ? const ['', '']
      : [for (final column in template.storedColumns) column.labelEn];
  return [
    header,
    for (var i = 0; i < dataRows; i++) List<String>.filled(header.length, ''),
  ];
}

class MatrixColumn {
  const MatrixColumn({
    required this.key,
    required this.labelNl,
    required this.labelEn,
    this.derived = false,
  });

  final String key;
  final String labelNl;
  final String labelEn;

  /// True for columns that must never be persisted (e.g. RPN).
  final bool derived;
}

class ImprovementTemplate {
  const ImprovementTemplate({
    required this.id,
    required this.engine,
    required this.phase,
    required this.labelNl,
    required this.labelEn,
    required this.guidanceNl,
    required this.guidanceEn,
    required this.columns,
  });

  final String id;
  final String engine;
  final String phase;
  final String labelNl;
  final String labelEn;
  final String guidanceNl;
  final String guidanceEn;
  final List<MatrixColumn> columns;

  /// The columns that actually live in the file. A derived column (RPN) is
  /// rendered, never written — so it is absent here, and the stored row indices
  /// line up with this list.
  List<MatrixColumn> get storedColumns =>
      columns.where((c) => !c.derived).toList();

  String label(String lang) => lang.startsWith('nl') ? labelNl : labelEn;
  String guidance(String lang) =>
      lang.startsWith('nl') ? guidanceNl : guidanceEn;
}
