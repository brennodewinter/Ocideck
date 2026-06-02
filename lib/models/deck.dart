import 'slide.dart';
import 'settings.dart';

/// Traffic Light Protocol-classificatie (FIRST TLP 2.0) van een presentatie.
enum TlpLevel { none, clear, green, amber, amberStrict, red }

extension TlpLevelX on TlpLevel {
  /// De officiële markering die op de slides verschijnt ('' bij [none]).
  String get label {
    switch (this) {
      case TlpLevel.none:
        return '';
      case TlpLevel.clear:
        return 'TLP:CLEAR';
      case TlpLevel.green:
        return 'TLP:GREEN';
      case TlpLevel.amber:
        return 'TLP:AMBER';
      case TlpLevel.amberStrict:
        return 'TLP:AMBER+STRICT';
      case TlpLevel.red:
        return 'TLP:RED';
    }
  }

  /// Tekst voor de keuzelijst.
  String get menuLabel => this == TlpLevel.none ? 'Geen' : label;

  /// Stabiele sleutel voor opslag in de front matter.
  String get key {
    switch (this) {
      case TlpLevel.none:
        return 'none';
      case TlpLevel.clear:
        return 'clear';
      case TlpLevel.green:
        return 'green';
      case TlpLevel.amber:
        return 'amber';
      case TlpLevel.amberStrict:
        return 'amber+strict';
      case TlpLevel.red:
        return 'red';
    }
  }

  /// Officiële TLP 2.0-voorgrondkleur (ARGB). Achtergrond is altijd zwart.
  int get foreground {
    switch (this) {
      case TlpLevel.none:
        return 0x00000000;
      case TlpLevel.clear:
        return 0xFFFFFFFF;
      case TlpLevel.green:
        return 0xFF33FF00;
      case TlpLevel.amber:
      case TlpLevel.amberStrict:
        return 0xFFFFC000;
      case TlpLevel.red:
        return 0xFFFF2B2B;
    }
  }

  static TlpLevel fromKey(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'clear':
        return TlpLevel.clear;
      case 'green':
        return TlpLevel.green;
      case 'amber':
        return TlpLevel.amber;
      case 'amber+strict':
      case 'amberstrict':
        return TlpLevel.amberStrict;
      case 'red':
        return TlpLevel.red;
      default:
        return TlpLevel.none;
    }
  }
}

class Deck {
  final String title;
  final String theme;
  final bool paginate;
  final List<Slide> slides;
  final String? projectPath;
  final ThemeProfile themeProfile;

  // ── General presentation metadata (stored in the markdown front matter) ──
  final String author;
  final String organization;
  final String version;
  final String date;
  final String description;
  final String keywords;

  /// Traffic Light Protocol-classificatie van deze presentatie.
  final TlpLevel tlp;

  const Deck({
    required this.title,
    this.theme = 'ocideck',
    this.paginate = true,
    this.slides = const [],
    this.projectPath,
    this.themeProfile = const ThemeProfile(),
    this.author = '',
    this.organization = '',
    this.version = '',
    this.date = '',
    this.description = '',
    this.keywords = '',
    this.tlp = TlpLevel.none,
  });

  Deck copyWith({
    String? title,
    String? theme,
    bool? paginate,
    List<Slide>? slides,
    String? projectPath,
    ThemeProfile? themeProfile,
    bool clearProjectPath = false,
    String? author,
    String? organization,
    String? version,
    String? date,
    String? description,
    String? keywords,
    TlpLevel? tlp,
  }) {
    return Deck(
      title: title ?? this.title,
      theme: theme ?? this.theme,
      paginate: paginate ?? this.paginate,
      slides: slides ?? this.slides,
      projectPath: clearProjectPath ? null : (projectPath ?? this.projectPath),
      themeProfile: themeProfile ?? this.themeProfile,
      author: author ?? this.author,
      organization: organization ?? this.organization,
      version: version ?? this.version,
      date: date ?? this.date,
      description: description ?? this.description,
      keywords: keywords ?? this.keywords,
      tlp: tlp ?? this.tlp,
    );
  }
}
