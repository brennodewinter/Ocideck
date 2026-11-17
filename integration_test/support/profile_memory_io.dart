import 'dart:io';
import 'package:integration_test/integration_test.dart';

String get profilePlatform => Platform.operatingSystem;
Map<String, Object> profileMemory(String phase) => {
  'rss_${phase}_bytes': ProcessInfo.currentRss,
  if (phase == 'after') 'process_max_rss_bytes': ProcessInfo.maxRss,
};

Future<void> profileWatchPerformance(
  IntegrationTestWidgetsFlutterBinding binding,
  Future<void> Function() action, {
  required String reportKey,
}) => binding
    .watchPerformance(action, reportKey: reportKey)
    .timeout(const Duration(minutes: 2));
