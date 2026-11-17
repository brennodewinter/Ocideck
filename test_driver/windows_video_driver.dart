import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    final path = Platform.environment['VIDEO_RESULT_FILE'];
    if (path == null) throw StateError('VIDEO_RESULT_FILE missing');
    await File(
      path,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  },
);
