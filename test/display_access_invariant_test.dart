@Tags(['registration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('physical display access stays behind the shared snapshot (#3216)', () {
    const adapters = {
      'lib/widgets/presentation/display_info.dart',
      'lib/widgets/presentation/display_info_io.dart',
      'lib/widgets/presentation/display_info_web.dart',
    };
    final offenders = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll(r'\', '/');
      final code = file.readAsStringSync();
      if (!adapters.contains(path) &&
          RegExp(
            r'\b(getAllDisplays|getCurrentWindowCenter)\s*\(',
          ).hasMatch(code)) {
        offenders.add('$path: raw enumeration/center access');
      }
      if (path != 'lib/widgets/presentation/display_info_io.dart' &&
          RegExp(r'\bDisplayManager\s*\.').hasMatch(code)) {
        offenders.add('$path: independent native enumeration');
      }
      if (RegExp(r'\bpresenterScreen\s*:').hasMatch(code)) {
        offenders.add('$path: a display index crosses the native boundary');
      }
      if (path != 'lib/widgets/presentation/display_info.dart' &&
          RegExp(r'\.coverScreen\s*\(').hasMatch(code)) {
        offenders.add('$path: audience placement bypasses snapshot identity');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Use captureDisplaySnapshot/coverAudienceDisplay.',
    );
  });
}
