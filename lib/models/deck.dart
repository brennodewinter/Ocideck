import 'annotation.dart';
import 'slide.dart';
import 'settings.dart';

/// Traffic Light Protocol-classificatie (FIRST TLP 2.0) van een presentatie.
///
/// De volgorde loopt van minst naar meest beperkend; [TlpLevel.index] is dus
/// bruikbaar om niveaus te vergelijken.
enum TlpLevel { none, clear, green, amber, amberStrict, red }

/// Of [slide] getoond mag worden wanneer de presentatie op [presentationTlp]
/// wordt gedeeld. Een slide wordt achtergehouden zodra zijn eigen TLP-niveau
/// strenger (hoger) is dan het voor de presentatie gekozen niveau.
bool slideVisibleAtTlp(Slide slide, TlpLevel presentationTlp) =>
    slide.tlp.index <= presentationTlp.index;

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

  /// Annotatielaag: vrije-hand-tekeningen per slide, gekeyd op [Slide.id].
  /// Bewust géén onderdeel van de Marp-markdown — dit wordt los bewaard in een
  /// sidecar zodat het deck pure, uitwisselbare Marp blijft.
  final Map<String, List<InkStroke>> annotations;

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
    this.annotations = const {},
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
    Map<String, List<InkStroke>>? annotations,
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
      annotations: annotations ?? this.annotations,
    );
  }
}
