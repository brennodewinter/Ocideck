import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;

import '../models/chart.dart';
import '../utils/number_convention.dart';

typedef ChartCsvData = (
  List<String>,
  List<ChartSeries>, {
  List<String> unreadable,
  List<String> ambiguous,
});

const _maxChartCsvBytes = 2 * 1024 * 1024;
const _maxChartCsvCells = 100000;

Future<String> readChartCsv(PlatformFile file) async {
  if ((file.lengthSync() ?? 0) > _maxChartCsvBytes) {
    throw const FormatException('CSV exceeds the byte limit');
  }
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in file.readAsByteStream()) {
    if (chunk.length > _maxChartCsvBytes - bytes.length) {
      throw const FormatException('CSV exceeds the byte limit');
    }
    bytes.add(chunk);
  }
  return utf8.decode(bytes.takeBytes());
}

Future<ChartCsvData> parseChartCsv(
  String csv, {
  DecimalConvention? convention,
}) => compute(
  (input) =>
      parseCsv(input.$1, convention: input.$2, maxCells: _maxChartCsvCells),
  (csv, convention),
);
