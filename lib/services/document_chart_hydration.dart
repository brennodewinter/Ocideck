import 'dart:io';

import '../models/chart.dart';
import '../utils/log.dart';
import '../utils/markdown_blocks.dart';
import '../utils/project_path.dart';

/// Vouw de reeksdata van elk ` ```chart `-blok met een externe
/// `source: data/<naam>.json`-verwijzing **inline** terug het blok in, zodat de
/// tekst de cijfers draagt vóór de OciWacht-scan (DOCUMENT_MODE.md §11.2 stap 1,
/// §11.5 eis 2).
///
/// Dezelfde insluitingsbewaking als andere byte-exportpaden:
/// [resolveContainedRealPath] weigert naast `../` en absolute paden ook een
/// projectinterne symlink die buiten het project eindigt.
///
/// - `projectPath == null`, of een blok zonder `source`, of een blok dat de data
///   al inline draagt → ongewijzigd.
/// - Bestand ontbreekt of wordt geweigerd → blok blijft staan (geen crash), de
///   grafiek tekent later leeg zoals bij de dia-hydratatie.
Future<String> hydrateDocumentChartData(
  String body, {
  String? projectPath,
}) async {
  if (projectPath == null) return body;
  final matches = chartFencePattern.allMatches(body).toList();
  if (matches.isEmpty) return body;

  final buf = StringBuffer();
  var last = 0;
  for (final m in matches) {
    buf.write(body.substring(last, m.start));
    final inlined = await _inlineBlock(m.group(1)!, projectPath);
    buf.write('```chart\n$inlined\n```');
    last = m.end;
  }
  buf.write(body.substring(last));
  return buf.toString();
}

/// De kale spec-tekst van één ` ```chart `-blok met de externe data ingevouwen,
/// of ongewijzigd wanneer er niets te hydrateren valt of het niet kan.
Future<String> _inlineBlock(String inner, String projectPath) async {
  final spec = ChartSpec.parse(inner);
  if (spec.source == null || spec.hasInlineData) return inner;

  // De data-verwijzing moet binnen het project blijven — geen absolute paden of
  // `../`-uitbraken. Geweigerd → blok ongemoeid laten.
  final abs = resolveContainedRealPath(spec.source!, projectPath);
  if (abs == null) return inner;

  final file = File(abs);
  if (!await file.exists()) return inner;
  try {
    final raw = await file.readAsString();
    // [ChartSpec.withData] kiest op de extensie (JSON/CSV) en laat de spec
    // ongemoeid bij onleesbare inhoud; [toBlock] schrijft de cijfers weer inline.
    return spec.withData(raw, path: abs).toBlock();
  } catch (e, s) {
    // Onleesbaar bestand: laat het blok staan, net als de dia-hydratatie. De
    // grafiek tekent later leeg; hier is er geen interface om te waarschuwen.
    logError('hydrateDocumentChartData: read chart data file', e, s);
    return inner;
  }
}
