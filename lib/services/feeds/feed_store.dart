// Duurzame toestand van feed-abonnementen (#2931): welke feeds de
// gebruiker volgt, met welk interval, welke validators (ETag/
// Last-Modified) de laatste controle opleverde, en welke afleveringen
// al bekend of vers zijn.
//
// Serialisatie is JSON in SharedPreferences — hetzelfde domein en
// patroon als de overige app-instellingen. Modellen zijn puur Dart;
// wie ze opslaat (provider) staat in feed_provider.dart.
import 'dart:convert';

import 'feed_models.dart';

/// Wat de wachtrij met een aflevering doet.
///
/// * [seen] — bekend, maar nooit als nieuw gemeld (o.a. alles dat al in
///   de feed stond toen de gebruiker hem ging volgen).
/// * [fresh] — nieuw aangeboden door een controle; wacht op de gebruiker.
/// * [handled] — gedownload, getranscribeerd, transcript opgehaald of
///   bewust weggeklikt: uit de wachtrij.
enum FeedEpisodeStatus { seen, fresh, handled }

/// Eén bekende aflevering binnen een abonnement. [downloadedPath] is
/// bewust vluchtig (sessie): een stagingbestand hoeft een herstart niet
/// te overleven en een `mem:`-sleutel doet dat nooit — de status zegt
/// dan nog steeds eerlijk "nieuw", niet "gedownload".
class FeedEpisodeRecord {
  FeedEpisodeRecord({
    required this.key,
    required this.title,
    this.published,
    required this.enclosureUrl,
    required this.enclosureType,
    this.transcripts = const [],
    this.status = FeedEpisodeStatus.seen,
    this.autoDownloadFailed = false,
  });

  final String key;
  final String title;
  final DateTime? published;
  final Uri enclosureUrl;
  final String enclosureType;
  final List<FeedTranscriptLink> transcripts;
  FeedEpisodeStatus status;
  bool autoDownloadFailed;

  /// Sessie-pad van een opgehaalde enclosure (tempbestand of `mem:`-
  /// sleutel). Wordt niet gepersisteerd; zie het veldcommentaar hierboven.
  String? downloadedPath;

  Map<String, Object?> toJson() => {
    'key': key,
    'title': title,
    'published': published?.toIso8601String(),
    'enclosureUrl': enclosureUrl.toString(),
    'enclosureType': enclosureType,
    'transcripts': [
      for (final t in transcripts)
        {'url': t.url.toString(), 'type': t.type, 'language': t.language},
    ],
    'status': status.name,
    if (autoDownloadFailed) 'autoDownloadFailed': true,
  };

  static FeedEpisodeRecord? fromJson(Map<String, Object?> json) {
    final key = json['key'];
    final enclosure = json['enclosureUrl'];
    if (key is! String || enclosure is! String) return null;
    final uri = Uri.tryParse(enclosure);
    if (uri == null) return null;
    return FeedEpisodeRecord(
      key: key,
      title: json['title'] is String ? json['title'] as String : '',
      published: DateTime.tryParse('${json['published'] ?? ''}'),
      enclosureUrl: uri,
      enclosureType: '${json['enclosureType'] ?? ''}',
      transcripts: [
        for (final t in (json['transcripts'] as List?) ?? const [])
          if (t is Map && t['url'] is String)
            if (Uri.tryParse(t['url'] as String) case final u?)
              FeedTranscriptLink(
                url: u,
                type: '${t['type'] ?? ''}',
                language: t['language'] as String?,
              ),
      ],
      autoDownloadFailed: json['autoDownloadFailed'] == true,
      status:
          FeedEpisodeStatus.values.asNameMap()[json['status']] ??
          FeedEpisodeStatus.seen,
    );
  }
}

/// Eén gevolgde feed. [resolvedUrl] is het eindadres na omleidingen en
/// gaat vóór bij de controle; [feedUrl] blijft wat de gebruiker zelf
/// opgaf, ter uitleg.
class FeedSubscription {
  FeedSubscription({
    required this.feedUrl,
    required this.resolvedUrl,
    required this.title,
    required this.checkInterval,
    this.etag,
    this.lastModified,
    this.lastChecked,
    this.consecutiveFailures = 0,
    this.paused = false,
    this.autoDownload = false,
    Map<String, FeedEpisodeRecord>? episodes,
  }) : episodes = episodes ?? {};

  final Uri feedUrl;
  Uri resolvedUrl;
  String title;
  Duration checkInterval;

  /// Validators van de laatste 200 — gaan als If-None-Match/
  /// If-Modified-Since mee bij de volgende controle.
  String? etag;
  String? lastModified;
  DateTime? lastChecked;

  /// Opeenvolgende mislukte controles; drijft de back-off in
  /// [effectiveInterval] en markeert de rij in de dialoog.
  int consecutiveFailures;

  bool paused;

  /// Afzonderlijke abonnementskeuze: nieuwe afleveringen meteen zelf
  /// downloaden (naar staging). Uit = handmatig per aflevering — de
  /// standaard.
  bool autoDownload;

  /// Bekende afleveringen op sleutel — een hernoemde titel of gewijzigde
  /// enclosure-URL levert zo geen dubbele vermelding.
  final Map<String, FeedEpisodeRecord> episodes;

  /// Wanneer de volgende controle valt: het gekozen interval, verdubbeld
  /// per opeenvolgende mislukking met een plafond van een dag — geen
  /// melderstorm op een doodlopende host.
  Duration get effectiveInterval {
    var interval = checkInterval;
    for (var i = 0; i < consecutiveFailures && i < 8; i++) {
      interval *= 2;
    }
    return interval > const Duration(hours: 24)
        ? const Duration(hours: 24)
        : interval;
  }

  DateTime? get nextCheck => lastChecked?.add(effectiveInterval);

  int get freshCount =>
      episodes.values.where((e) => e.status == FeedEpisodeStatus.fresh).length;

  Map<String, Object?> toJson() => {
    'feedUrl': feedUrl.toString(),
    'resolvedUrl': resolvedUrl.toString(),
    'title': title,
    'checkIntervalSeconds': checkInterval.inSeconds,
    'etag': etag,
    'lastModified': lastModified,
    'lastChecked': lastChecked?.toIso8601String(),
    'consecutiveFailures': consecutiveFailures,
    'paused': paused,
    'autoDownload': autoDownload,
    'episodes': [for (final e in episodes.values) e.toJson()],
  };

  static FeedSubscription? fromJson(Map<String, Object?> json) {
    final feed = json['feedUrl'];
    final resolved = json['resolvedUrl'];
    if (feed is! String || resolved is! String) return null;
    final feedUri = Uri.tryParse(feed);
    final resolvedUri = Uri.tryParse(resolved);
    if (feedUri == null || resolvedUri == null) return null;
    final intervalSeconds = json['checkIntervalSeconds'];
    return FeedSubscription(
      feedUrl: feedUri,
      resolvedUrl: resolvedUri,
      title: json['title'] is String ? json['title'] as String : '',
      checkInterval: Duration(
        seconds: intervalSeconds is int ? intervalSeconds : 3600,
      ),
      etag: json['etag'] as String?,
      lastModified: json['lastModified'] as String?,
      lastChecked: DateTime.tryParse('${json['lastChecked'] ?? ''}'),
      consecutiveFailures: json['consecutiveFailures'] is int
          ? json['consecutiveFailures'] as int
          : 0,
      paused: json['paused'] == true,
      autoDownload: json['autoDownload'] == true,
      episodes: {
        for (final e in (json['episodes'] as List?) ?? const [])
          if (e is Map<String, Object?>)
            for (final rec in [?FeedEpisodeRecord.fromJson(e)]) rec.key: rec,
      },
    );
  }
}

/// Lees/schrijf de abonnementenlijst als één JSON-string — atomaire
/// opslag, geen gedeeltelijke velden.
class FeedStoreCodec {
  const FeedStoreCodec();

  static const prefsKey = 'podcastFeedSubscriptions';

  String encode(List<FeedSubscription> subscriptions) =>
      jsonEncode([for (final sub in subscriptions) sub.toJson()]);

  List<FeedSubscription> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [
        for (final entry in jsonDecode(raw) as List)
          if (entry is Map<String, Object?>) ?FeedSubscription.fromJson(entry),
      ];
    } on Object {
      // Beschadigde opslag is geen reden de app te laten vallen: dan is
      // er eenvoudigweg nog geen abonnement bekend.
      return const [];
    }
  }
}
