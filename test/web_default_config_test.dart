@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'default web configuration is served but enables no optional features',
    () {
      final config = jsonDecode(
        File('web/ocideck-web-config.json').readAsStringSync(),
      );
      expect(config, isA<Map<String, dynamic>>());
      expect(config, isEmpty);
    },
  );
}
