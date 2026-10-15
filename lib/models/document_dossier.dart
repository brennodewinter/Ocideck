/// A dossier index. Entries point to their original files.
/// Unknown keys survive a load/save cycle so newer producers remain compatible.
class DocumentDossier {
  const DocumentDossier({
    required this.title,
    required this.entries,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
    this.startNumber = 1,
    this.extra = const {},
  });

  final String title;
  final List<DossierEntry> entries;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String description;
  final int startNumber;
  final Map<String, dynamic> extra;

  List<int> get displayNumbers {
    final reserved = entries
        .map((entry) => entry.numberOverride)
        .whereType<int>()
        .toSet();
    final used = <int>{};
    var next = startNumber;
    return [
      for (final entry in entries)
        if (entry.numberOverride case final int override)
          override
        else
          (() {
            while (reserved.contains(next) || used.contains(next)) {
              next++;
            }
            final number = next++;
            used.add(number);
            return number;
          })(),
    ];
  }

  int numberFor(int index) => displayNumbers[index];

  DocumentDossier copyWith({
    String? title,
    List<DossierEntry>? entries,
    DateTime? updatedAt,
    String? description,
    int? startNumber,
  }) => DocumentDossier(
    title: title ?? this.title,
    entries: entries ?? this.entries,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    description: description ?? this.description,
    startNumber: startNumber ?? this.startNumber,
    extra: extra,
  );

  factory DocumentDossier.fromJson(Map<String, dynamic> json) {
    final entries = json['entries'];
    if (json['version'] != 1 && json['version'] != 2 ||
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
      description: json['description'] as String? ?? '',
      startNumber: json['startNumber'] as int? ?? 1,
      extra: Map.of(json)
        ..removeWhere(
          (key, _) => {
            'version',
            'title',
            'entries',
            'createdAt',
            'updatedAt',
            'description',
            'startNumber',
          }.contains(key),
        ),
    );
  }

  Map<String, dynamic> toJson() => {
    ...extra,
    'version': 2,
    'title': title,
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'description': description,
    'startNumber': startNumber,
  };
}

class DossierEntry {
  const DossierEntry({
    required this.id,
    required this.title,
    required this.relativePath,
    required this.sha256,
    this.description = '',
    this.documentDate,
    this.author = '',
    this.sourcePath,
    this.sourceRelativePath,
    this.originalName,
    this.sizeBytes,
    this.checkedAt,
    this.hashHistory = const [],
    this.numberOverride,
    this.extra = const {},
  });

  final String id;
  final String title;
  final String relativePath;
  final String sha256;
  final String description;

  /// ISO calendar date from the document, without an inferred time zone.
  final String? documentDate;
  final String author;

  /// Absolute path of the original source. Null for a legacy copied attachment.
  final String? sourcePath;

  /// Location relative to the dossier when the original is nearby.
  final String? sourceRelativePath;
  final String? originalName;
  final int? sizeBytes;
  final DateTime? checkedAt;
  final List<DossierHashRevision> hashHistory;
  final int? numberOverride;
  final Map<String, dynamic> extra;

  DossierEntry copyWith({
    String? title,
    String? relativePath,
    String? sha256,
    String? description,
    String? documentDate,
    bool clearDocumentDate = false,
    String? author,
    int? sizeBytes,
    DateTime? checkedAt,
    List<DossierHashRevision>? hashHistory,
    int? numberOverride,
    bool clearNumberOverride = false,
  }) => DossierEntry(
    id: id,
    title: title ?? this.title,
    relativePath: relativePath ?? this.relativePath,
    sha256: sha256 ?? this.sha256,
    description: description ?? this.description,
    documentDate: clearDocumentDate ? null : documentDate ?? this.documentDate,
    author: author ?? this.author,
    sourcePath: sourcePath,
    sourceRelativePath: sourceRelativePath,
    originalName: originalName,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    checkedAt: checkedAt ?? this.checkedAt,
    hashHistory: hashHistory ?? this.hashHistory,
    numberOverride: clearNumberOverride
        ? null
        : numberOverride ?? this.numberOverride,
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
    final history = json['hashHistory'];
    if (json['sourcePath'] != null && json['sourcePath'] is! String ||
        json['sourceRelativePath'] != null &&
            json['sourceRelativePath'] is! String ||
        json['originalName'] != null && json['originalName'] is! String ||
        json['sizeBytes'] != null &&
            (json['sizeBytes'] is! int || (json['sizeBytes'] as int) < 0) ||
        json['checkedAt'] != null && json['checkedAt'] is! String ||
        json['description'] != null && json['description'] is! String ||
        json['documentDate'] != null &&
            (json['documentDate'] is! String ||
                !validDocumentDate(json['documentDate'] as String)) ||
        json['author'] != null && json['author'] is! String ||
        history != null && history is! List) {
      throw const FormatException('Ongeldig dossieritem');
    }
    return DossierEntry(
      id: json['id'] as String,
      title: json['title'] as String,
      relativePath: json['relativePath'] as String,
      sha256: (json['sha256'] as String).toLowerCase(),
      description: json['description'] as String? ?? '',
      documentDate: json['documentDate'] as String?,
      author: json['author'] as String? ?? '',
      sourcePath: json['sourcePath'] as String?,
      sourceRelativePath: json['sourceRelativePath'] as String?,
      originalName: json['originalName'] as String?,
      sizeBytes: json['sizeBytes'] as int?,
      checkedAt: json['checkedAt'] == null
          ? null
          : DateTime.parse(json['checkedAt'] as String),
      hashHistory: history == null
          ? const <DossierHashRevision>[]
          : (history as List)
                .map<DossierHashRevision>(
                  (dynamic e) =>
                      DossierHashRevision.fromJson(e as Map<String, dynamic>),
                )
                .toList(),
      numberOverride: json['numberOverride'] as int?,
      extra: Map.of(json)
        ..removeWhere(
          (key, _) => {
            'id',
            'title',
            'relativePath',
            'sha256',
            'description',
            'documentDate',
            'author',
            'sourcePath',
            'sourceRelativePath',
            'originalName',
            'sizeBytes',
            'checkedAt',
            'hashHistory',
            'numberOverride',
          }.contains(key),
        ),
    );
  }

  Map<String, dynamic> toJson() => {
    ...extra,
    'id': id,
    'title': title,
    'relativePath': relativePath,
    'sha256': sha256,
    if (description.isNotEmpty) 'description': description,
    if (documentDate != null) 'documentDate': documentDate,
    if (author.isNotEmpty) 'author': author,
    if (sourcePath != null) 'sourcePath': sourcePath,
    if (sourceRelativePath != null) 'sourceRelativePath': sourceRelativePath,
    if (originalName != null) 'originalName': originalName,
    if (sizeBytes != null) 'sizeBytes': sizeBytes,
    if (checkedAt != null) 'checkedAt': checkedAt!.toUtc().toIso8601String(),
    'hashHistory': hashHistory.map((revision) => revision.toJson()).toList(),
    if (numberOverride != null) 'numberOverride': numberOverride,
  };

  static bool validDocumentDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
    final parsed = DateTime.tryParse(value);
    return parsed != null &&
        parsed.year == int.parse(value.substring(0, 4)) &&
        parsed.month == int.parse(value.substring(5, 7)) &&
        parsed.day == int.parse(value.substring(8, 10));
  }
}

class DossierHashRevision {
  const DossierHashRevision({required this.sha256, required this.recordedAt});
  final String sha256;
  final DateTime recordedAt;

  factory DossierHashRevision.fromJson(Map<String, dynamic> json) {
    final hash = json['sha256'];
    final time = json['recordedAt'];
    if (hash is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash) ||
        time is! String) {
      throw const FormatException('Ongeldige hashgeschiedenis');
    }
    return DossierHashRevision(
      sha256: hash.toLowerCase(),
      recordedAt: DateTime.parse(time),
    );
  }

  Map<String, dynamic> toJson() => {
    'sha256': sha256,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
  };
}
