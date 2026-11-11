import 'dart:convert';

import 'log.dart';

/// Serialiseer een lijst voor het prefs-domein: JSON-array van per-item
/// [toJson]. Het mirrorbeeld van [decodeJsonList].
String encodeJsonList<T>(
  List<T> list,
  Map<String, Object?> Function(T) toJson,
) => jsonEncode([for (final x in list) toJson(x)]);

/// Lees een lijst terug die met [encodeJsonList] is geschreven. Een onleesbare
/// waarde levert een lege lijst op; losse onleesbare items vallen weg — ook
/// wanneer [fromJson] `null` teruggeeft (bijv. StorageConnection bij een
/// onbekende soort) of gooit: één rotte kost de geldige buren niet (#2888).
/// Optionele [keep] filtert daarna verder (bijv. "pad mag niet leeg zijn").
///
/// Wie [refused] meegeeft krijgt de ruwe waarden die wegvielen — een niet-Map
/// item, een item waar [fromJson] over struikelde, of bij een failliet
/// topniveau de hele oorspronkelijke string — zodat de aanroeper ze kan
/// bewaren in plaats van ze bij de eerstvolgende schrijfactie te verliezen.
List<T> decodeJsonList<T>(
  String? json,
  T? Function(Map<String, Object?>) fromJson, {
  bool Function(T)? keep,
  String label = 'decodeJsonList',
  List<Object?>? refused,
}) {
  if (json == null || json.isEmpty) return const [];
  final decoded = <T>[];
  try {
    final list = jsonDecode(json);
    if (list is! List) {
      refused?.add(json);
      return const [];
    }
    for (final item in list) {
      if (item is! Map) {
        refused?.add(item);
        continue;
      }
      try {
        final value = fromJson(Map<String, Object?>.from(item));
        if (value != null) {
          decoded.add(value);
        } else {
          refused?.add(item);
        }
      } catch (e) {
        refused?.add(item);
        logWarning('$label: onleesbaar item weggelaten', e);
      }
    }
  } catch (e) {
    refused?.add(json);
    logWarning('$label: onleesbare lijst', e);
    return const [];
  }
  return decoded.where(keep ?? (_) => true).toList();
}
