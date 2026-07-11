import 'dart:convert';

import '../utils/log.dart';

/// Eén opslaglocatie in de gebruiker zijn bibliotheek: een vrije [name]
/// (bijv. "Privé" of "Werk") plus het [path] op schijf. De naam laat de
/// gebruiker onderscheid maken zonder het volledige pad te hoeven lezen; ze
/// dient tegelijk als startpunt voor openen/opslaan en als zoekwortel voor de
/// presentatie- en afbeeldingenbibliotheek. Vervangt de vroegere enkele
/// `homeDirectory`-instelling.
class LibraryFolder {
  final String name;
  final String path;

  const LibraryFolder({required this.name, required this.path});

  LibraryFolder copyWith({String? name, String? path}) =>
      LibraryFolder(name: name ?? this.name, path: path ?? this.path);

  Map<String, Object?> toJson() => {'name': name, 'path': path};

  factory LibraryFolder.fromJson(Map<String, Object?> json) => LibraryFolder(
    name: json['name'] as String? ?? '',
    path: json['path'] as String? ?? '',
  );

  /// Serialiseer een lijst voor het prefs-domein.
  static String encodeList(List<LibraryFolder> folders) =>
      jsonEncode([for (final f in folders) f.toJson()]);

  /// Lees een lijst terug; een onleesbare waarde levert een lege lijst op, en
  /// items zonder pad vallen weg (een bibliotheek zonder map is zinloos).
  static List<LibraryFolder> decodeList(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map)
            LibraryFolder.fromJson(Map<String, Object?>.from(item)),
      ].where((f) => f.path.isNotEmpty).toList();
    } catch (e) {
      logWarning('LibraryFolder.decodeList: onleesbare bibliothekenlijst', e);
      return const [];
    }
  }
}
