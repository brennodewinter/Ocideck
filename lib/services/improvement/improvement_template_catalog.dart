// Offline Procesverbetering artefact catalog (PROCESS_IMPROVEMENT.md §2 / §8).
//
// Markdown sources in `assets/improvement/templates/*.md` are the authoring
// truth; `tool/build_improvement_templates.dart` emits
// `assets/improvement/templates.json` and the matching Dart floor. Adding a
// template = drop in a file and rebuild — no hand-edited Dart list.
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../../utils/log.dart';
import 'canvas_spec.dart';
import 'flow_spec.dart';
import 'improvement_templates_floor.g.dart';
import 'matrix_spec.dart';
import 'tree_spec.dart';

/// Bundled artefact templates for matrix / canvas / tree / flow engines.
///
/// The [floor] is always available (same bytes as the last build of the JSON
/// asset). [ensureLoaded] replaces it with the asset when present — fail-soft
/// on a missing or corrupt asset so authoring never crashes offline.
class ImprovementTemplateCatalog {
  ImprovementTemplateCatalog._() {
    _applyJson(kImprovementTemplatesFloorJson);
  }

  static final ImprovementTemplateCatalog instance =
      ImprovementTemplateCatalog._();

  static const _assetKey = 'assets/improvement/templates.json';

  List<ImprovementTemplate> _matrix = const [];
  List<CanvasTemplate> _canvas = const [];
  List<TreeTemplate> _tree = const [];
  List<FlowTemplate> _flow = const [];
  bool _assetLoaded = false;

  List<ImprovementTemplate> get matrixTemplates => _matrix;
  List<CanvasTemplate> get canvasTemplates => _canvas;
  List<TreeTemplate> get treeTemplates => _tree;
  List<FlowTemplate> get flowTemplates => _flow;

  ImprovementTemplate? matrixById(String id) {
    for (final t in _matrix) {
      if (t.id == id) return t;
    }
    return null;
  }

  CanvasTemplate? canvasById(String id) {
    for (final t in _canvas) {
      if (t.id == id) return t;
    }
    return null;
  }

  TreeTemplate? treeById(String id) {
    for (final t in _tree) {
      if (t.id == id) return t;
    }
    return null;
  }

  FlowTemplate? flowById(String id) {
    for (final t in _flow) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Load the bundled JSON asset over the floor. Idempotent; safe to call when
  /// the module is revealed or a picker opens.
  Future<void> ensureLoaded({AssetBundle? bundle}) async {
    if (_assetLoaded) return;
    try {
      final raw = await (bundle ?? rootBundle).loadString(_assetKey);
      _applyJson(raw);
      _assetLoaded = true;
    } catch (e) {
      logError('ImprovementTemplateCatalog.ensureLoaded', e);
    }
  }

  @visibleForTesting
  void resetForTest() {
    _assetLoaded = false;
    _applyJson(kImprovementTemplatesFloorJson);
  }

  @visibleForTesting
  void loadJsonForTest(String raw) {
    _applyJson(raw);
    _assetLoaded = true;
  }

  void _applyJson(String raw) {
    final decoded = jsonDecode(raw);
    final list = decoded is Map<String, dynamic>
        ? decoded['templates'] as List? ?? const []
        : decoded as List;
    final matrix = <ImprovementTemplate>[];
    final canvas = <CanvasTemplate>[];
    final tree = <TreeTemplate>[];
    final flow = <FlowTemplate>[];
    for (final row in list) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      switch (map['engine'] as String? ?? '') {
        case 'matrix':
          matrix.add(_parseMatrix(map));
        case 'canvas':
          canvas.add(_parseCanvas(map));
        case 'tree':
          tree.add(_parseTree(map));
        case 'flow':
          flow.add(_parseFlow(map));
      }
    }
    _matrix = matrix;
    _canvas = canvas;
    _tree = tree;
    _flow = flow;
  }
}

ImprovementTemplate _parseMatrix(Map<String, dynamic> map) {
  final columns = <MatrixColumn>[];
  for (final c in map['columns'] as List? ?? const []) {
    if (c is! Map) continue;
    final col = Map<String, dynamic>.from(c);
    final label = Map<String, dynamic>.from(col['label'] as Map? ?? {});
    columns.add(
      MatrixColumn(
        key: col['key'] as String? ?? '',
        labelNl: label['nl'] as String? ?? '',
        labelEn: label['en'] as String? ?? '',
        derived: col['derived'] == true,
      ),
    );
  }
  final label = Map<String, dynamic>.from(map['label'] as Map? ?? {});
  final guidance = Map<String, dynamic>.from(map['guidance'] as Map? ?? {});
  return ImprovementTemplate(
    id: map['id'] as String? ?? '',
    engine: 'matrix',
    phase: map['phase'] as String? ?? '',
    labelNl: label['nl'] as String? ?? '',
    labelEn: label['en'] as String? ?? '',
    guidanceNl: guidance['nl'] as String? ?? '',
    guidanceEn: guidance['en'] as String? ?? '',
    columns: columns,
  );
}

CanvasTemplate _parseCanvas(Map<String, dynamic> map) {
  final label = Map<String, dynamic>.from(map['label'] as Map? ?? {});
  final guidance = Map<String, dynamic>.from(map['guidance'] as Map? ?? {});
  final axes = Map<String, dynamic>.from(map['axes'] as Map? ?? {});
  Map<String, dynamic> axis(String key) =>
      Map<String, dynamic>.from(axes[key] as Map? ?? {});
  final regions = <CanvasRegion>[];
  for (final r in map['regions'] as List? ?? const []) {
    if (r is! Map) continue;
    final region = Map<String, dynamic>.from(r);
    final rLabel = Map<String, dynamic>.from(region['label'] as Map? ?? {});
    regions.add(
      CanvasRegion(
        key: region['key'] as String? ?? '',
        labelNl: rLabel['nl'] as String? ?? '',
        labelEn: rLabel['en'] as String? ?? '',
      ),
    );
  }
  final layoutToken = map['layout'] as String? ?? 'regions';
  final layout = switch (layoutToken) {
    'quadrant' => CanvasLayout.quadrant,
    'board' => CanvasLayout.board,
    _ => CanvasLayout.regions,
  };
  return CanvasTemplate(
    id: map['id'] as String? ?? '',
    layout: layout,
    phase: map['phase'] as String? ?? '',
    labelNl: label['nl'] as String? ?? '',
    labelEn: label['en'] as String? ?? '',
    guidanceNl: guidance['nl'] as String? ?? '',
    guidanceEn: guidance['en'] as String? ?? '',
    regions: regions,
    axisXLowNl: axis('xLow')['nl'] as String? ?? '',
    axisXLowEn: axis('xLow')['en'] as String? ?? '',
    axisXHighNl: axis('xHigh')['nl'] as String? ?? '',
    axisXHighEn: axis('xHigh')['en'] as String? ?? '',
    axisYLowNl: axis('yLow')['nl'] as String? ?? '',
    axisYLowEn: axis('yLow')['en'] as String? ?? '',
    axisYHighNl: axis('yHigh')['nl'] as String? ?? '',
    axisYHighEn: axis('yHigh')['en'] as String? ?? '',
  );
}

TreeTemplate _parseTree(Map<String, dynamic> map) {
  final label = Map<String, dynamic>.from(map['label'] as Map? ?? {});
  final guidance = Map<String, dynamic>.from(map['guidance'] as Map? ?? {});
  final bullets = [
    for (final b in map['starterBullets'] as List? ?? const [])
      if (b is String) b,
  ];
  return TreeTemplate(
    id: map['id'] as String? ?? '',
    defaultLayout: treeLayoutFromToken(
      map['defaultLayout'] as String? ?? 'tree',
    ),
    phase: map['phase'] as String? ?? '',
    labelNl: label['nl'] as String? ?? '',
    labelEn: label['en'] as String? ?? '',
    guidanceNl: guidance['nl'] as String? ?? '',
    guidanceEn: guidance['en'] as String? ?? '',
    starterBullets: bullets,
  );
}

FlowTemplate _parseFlow(Map<String, dynamic> map) {
  final label = Map<String, dynamic>.from(map['label'] as Map? ?? {});
  final guidance = Map<String, dynamic>.from(map['guidance'] as Map? ?? {});
  final bullets = [
    for (final b in map['starterBullets'] as List? ?? const [])
      if (b is String) b,
  ];
  return FlowTemplate(
    id: map['id'] as String? ?? '',
    defaultLayout: flowLayoutFromToken(
      map['defaultLayout'] as String? ?? 'flow',
    ),
    phase: map['phase'] as String? ?? '',
    labelNl: label['nl'] as String? ?? '',
    labelEn: label['en'] as String? ?? '',
    guidanceNl: guidance['nl'] as String? ?? '',
    guidanceEn: guidance['en'] as String? ?? '',
    starterBullets: bullets,
  );
}
