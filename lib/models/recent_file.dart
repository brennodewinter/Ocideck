import 'dart:convert';

import 'deck.dart';
import '../utils/log.dart';

/// Eén item in de "recente presentaties"-lijst: naast het pad ook de
/// metadata die terugvinden makkelijk maakt (wanneer geopend, hoeveel
/// slides, welk TLP-niveau, laatst geëxporteerd als). De metadata wordt
/// bijgewerkt bij openen en exporteren; het bestand zelf blijft de bron
/// van de inhoud.
class RecentFile {
  final String path;

  /// Wanneer dit bestand voor het laatst in de app is geopend.
  final DateTime? openedAt;

  /// Aantal slides bij de laatste keer openen (0 = onbekend, bijv. na
  /// migratie van de oude paden-lijst).
  final int slideCount;

  final TlpLevel tlp;

  /// Label van het laatst geëxporteerde formaat ("PDF", "PPTX", "HTML");
  /// null zolang er nooit geëxporteerd is.
  final String? lastExportFormat;
  final DateTime? lastExportAt;

  const RecentFile({
    required this.path,
    this.openedAt,
    this.slideCount = 0,
    this.tlp = TlpLevel.none,
    this.lastExportFormat,
    this.lastExportAt,
  });

  RecentFile copyWith({
    DateTime? openedAt,
    int? slideCount,
    TlpLevel? tlp,
    String? lastExportFormat,
    DateTime? lastExportAt,
  }) {
    return RecentFile(
      path: path,
      openedAt: openedAt ?? this.openedAt,
      slideCount: slideCount ?? this.slideCount,
      tlp: tlp ?? this.tlp,
      lastExportFormat: lastExportFormat ?? this.lastExportFormat,
      lastExportAt: lastExportAt ?? this.lastExportAt,
    );
  }

  Map<String, Object?> toJson() => {
    'path': path,
    if (openedAt != null) 'openedAt': openedAt!.toIso8601String(),
    'slideCount': slideCount,
    'tlp': tlp.key,
    if (lastExportFormat != null) 'lastExportFormat': lastExportFormat,
    if (lastExportAt != null)
      'lastExportAt': lastExportAt!.toIso8601String(),
  };

  factory RecentFile.fromJson(Map<String, Object?> json) {
    return RecentFile(
      path: json['path'] as String? ?? '',
      openedAt: json['openedAt'] is String
          ? DateTime.tryParse(json['openedAt'] as String)
          : null,
      slideCount: (json['slideCount'] as num?)?.toInt() ?? 0,
      tlp: TlpLevelX.fromKey(json['tlp'] as String? ?? ''),
      lastExportFormat: json['lastExportFormat'] as String?,
      lastExportAt: json['lastExportAt'] is String
          ? DateTime.tryParse(json['lastExportAt'] as String)
          : null,
    );
  }

  /// Serialiseer een lijst voor het prefs-domein.
  static String encodeList(List<RecentFile> files) =>
      jsonEncode([for (final f in files) f.toJson()]);

  /// Lees een lijst terug; een onleesbare waarde levert een lege lijst op
  /// (de recente lijst is comfort, geen data om op te breken).
  static List<RecentFile> decodeList(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map)
            RecentFile.fromJson(Map<String, Object?>.from(item)),
      ].where((f) => f.path.isNotEmpty).toList();
    } catch (e) {
      logWarning('RecentFile.decodeList: onleesbare recente-lijst', e);
      return const [];
    }
  }

  /// Migratie van de oude opslagvorm (alleen paden, geen metadata).
  static List<RecentFile> fromLegacyPaths(List<String> paths) => [
    for (final path in paths)
      if (path.isNotEmpty) RecentFile(path: path),
  ];
}
