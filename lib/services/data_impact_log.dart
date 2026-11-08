import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/log.dart';

/// Begrensd toestemmingslog, ook op web waar geen lokaal logbestand bestaat.
/// De vaste ids bevatten geen documentinhoud, gebruikersnamen of server-URL’s.
class DataImpactLog {
  static const key = 'dataImpactLogV1';

  static Future<void> record(String id, String decision) async {
    logInfo('data-impact v1: $id $decision');
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = prefs.getStringList(key) ?? [];
      entries.add(
        jsonEncode({
          'at': DateTime.now().toUtc().toIso8601String(),
          'id': id,
          'version': 1,
          'decision': decision,
        }),
      );
      if (entries.length > 200) entries.removeRange(0, entries.length - 200);
      if (!await prefs.setStringList(key, entries)) {
        logWarning('data-impact: audit write rejected');
      }
    } catch (e) {
      logWarning('data-impact: audit write failed', e);
    }
  }
}
