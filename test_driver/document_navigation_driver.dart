import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final path = Platform.environment['NAVIGATION_RESULT_FILE'];
    if (path == null) throw StateError('NAVIGATION_RESULT_FILE ontbreekt');
    await File(
      path,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  },
);
