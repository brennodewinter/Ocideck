// Fails when the generated floor drifts from assets/improvement/templates.json.
// Rebuild with: dart run tool/build_improvement_templates.dart
import 'dart:convert';
import 'dart:io';

void main() {
  final jsonFile = File('assets/improvement/templates.json');
  final floorFile = File(
    'lib/services/improvement/improvement_templates_floor.g.dart',
  );
  if (!jsonFile.existsSync() || !floorFile.existsSync()) {
    stderr.writeln(
      'missing improvement templates asset or floor — run:\n'
      '  dart run tool/build_improvement_templates.dart',
    );
    exit(1);
  }
  var jsonText = jsonFile.readAsStringSync();
  if (jsonText.endsWith('\n')) {
    jsonText = jsonText.substring(0, jsonText.length - 1);
  }
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map || decoded['templates'] is! List) {
    stderr.writeln('templates.json: missing templates array');
    exit(1);
  }
  final count = (decoded['templates'] as List).length;
  if (count < 1) {
    stderr.writeln('templates.json: empty catalog');
    exit(1);
  }
  final floor = floorFile.readAsStringSync();
  final expected = jsonEncode(jsonText);
  if (!floor.contains(expected)) {
    stderr.writeln(
      'improvement templates floor is out of sync with templates.json.\n'
      'Run: dart run tool/build_improvement_templates.dart',
    );
    exit(1);
  }
  stdout.writeln('improvement templates ok ($count)');
}
