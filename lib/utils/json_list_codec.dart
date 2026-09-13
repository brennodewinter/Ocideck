import 'dart:convert';

import 'log.dart';

/// Serialiseer een lijst voor het prefs-domein: JSON-array van per-item
/// [toJson]. Het mirrorbeeld van [decodeJsonList].
String encodeJsonList<T>(
  List<T> list,
  Map<String, Object?> Function(T) toJson,
) =>
    jsonEncode([for (final x in list) toJson(x)]);

/// Lees een lijst terug die met [encodeJsonList] is geschreven. Een onleesbare
/// waarde levert een lege lijst op; losse onleesbare items vallen weg via
/// [whereType] — ook als [fromJson] `null` teruggeeft (bijv. StorageConnection
/// bij een onbekende soort). Optionele [keep] filtert daarna verder (bijv.
/// "pad mag niet leeg zijn").
List<T> decodeJsonList<T>(
  String? json,
  T? Function(Map<String, Object?>) fromJson, {
  bool Function(T)? keep,
  String label = 'decodeJsonList',
}) {
  if (json == null || json.isEmpty) return const [];
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (item is Map) fromJson(Map<String, Object?>.from(item)),
    ].whereType<T>().where(keep ?? (_) => true).toList();
  } catch (e) {
    logWarning('$label: onleesbare lijst', e);
    return const [];
  }
}
