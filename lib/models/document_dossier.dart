/// A portable dossier index. Files live beside the index in `attachments/`.
/// Unknown keys survive a load/save cycle so newer producers remain compatible.
class DocumentDossier {
  const DocumentDossier({
    required this.title,
    required this.entries,
    required this.createdAt,
    required this.updatedAt,
    this.extra = const {},
  });

  final String title;
  final List<DossierEntry> entries;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic> extra;

  DocumentDossier copyWith({
    String? title,
    List<DossierEntry>? entries,
    DateTime? updatedAt,
  }) => DocumentDossier(
    title: title ?? this.title,
    entries: entries ?? this.entries,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    extra: extra,
  );

  factory DocumentDossier.fromJson(Map<String, dynamic> json) {
    final entries = json['entries'];
    if (json['version'] != 1 ||
        json['title'] is! String ||
        entries is! List ||
        json['createdAt'] is! String ||
        json['updatedAt'] is! String) {
      throw const FormatException('Ongeldig dossierformaat');
    }
    return DocumentDossier(
      title: json['title'] as String,
      entries: entries.map((e) {
        if (e is! Map<String, dynamic>) {
          throw const FormatException('Ongeldig dossieritem');
        }
        return DossierEntry.fromJson(e);
      }).toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      extra: Map.of(json)
        ..removeWhere(
          (key, _) => {
            'version',
            'title',
            'entries',
            'createdAt',
            'updatedAt',
          }.contains(key),
        ),
    );
  }

  Map<String, dynamic> toJson() => {
    ...extra,
    'version': 1,
    'title': title,
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

class DossierEntry {
  const DossierEntry({
    required this.id,
    required this.title,
    required this.relativePath,
    required this.sha256,
    this.extra = const {},
  });

  final String id;
  final String title;
  final String relativePath;
  final String sha256;
  final Map<String, dynamic> extra;

  DossierEntry copyWith({
    String? title,
    String? relativePath,
    String? sha256,
  }) => DossierEntry(
    id: id,
    title: title ?? this.title,
    relativePath: relativePath ?? this.relativePath,
    sha256: sha256 ?? this.sha256,
    extra: extra,
  );

  factory DossierEntry.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String ||
        json['title'] is! String ||
        json['relativePath'] is! String ||
        json['sha256'] is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(json['sha256'] as String)) {
      throw const FormatException('Ongeldig dossieritem');
    }
    return DossierEntry(
      id: json['id'] as String,
      title: json['title'] as String,
      relativePath: json['relativePath'] as String,
      sha256: (json['sha256'] as String).toLowerCase(),
      extra: Map.of(json)
        ..removeWhere(
          (key, _) => {'id', 'title', 'relativePath', 'sha256'}.contains(key),
        ),
    );
  }

  Map<String, dynamic> toJson() => {
    ...extra,
    'id': id,
    'title': title,
    'relativePath': relativePath,
    'sha256': sha256,
  };
}
