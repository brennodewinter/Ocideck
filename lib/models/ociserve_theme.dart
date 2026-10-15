import 'package:flutter/foundation.dart';

/// Een stijlprofiel in het themaregister van de organisatie (#2429).
/// [definition] is de ondoorzichtige ThemeProfile-JSON van OciDeck — de server
/// controleert alleen dat het een object is en levert hem onveranderd terug.
@immutable
class OciServeTheme {
  const OciServeTheme({
    required this.id,
    required this.name,
    required this.definition,
    required this.isBuiltin,
  });

  final String id;
  final String name;
  final Map<String, Object?> definition;

  /// De vier ingebouwde profielen zijn read-only — de server weigert
  /// bijwerken en verwijderen met 409.
  final bool isBuiltin;

  factory OciServeTheme.fromJson(Map<String, Object?> json) {
    final id = (json['id'] as String? ?? '').trim();
    final name = (json['name'] as String? ?? '').trim();
    final definition = json['definition'];
    if (id.isEmpty || name.isEmpty || definition is! Map) {
      throw const FormatException('incomplete theme');
    }
    return OciServeTheme(
      id: id,
      name: name,
      definition: Map<String, Object?>.from(definition),
      isBuiltin: json['is_builtin'] == true,
    );
  }
}
