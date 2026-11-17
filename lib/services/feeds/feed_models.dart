// Datamodel voor podcastfeeds (#2931): wat een herkende feed aan de
// schil teruggeeft — titel, bron en afleveringen met hun audio-/video-
// enclosure en eventuele `podcast:transcript`-verwijzingen.
//
// Puur data, geen IO: de parser vult dit, de store persisteert er een
// afgeleide van, en de dialoog toont het.

/// Een `podcast:transcript`-verwijzing uit de feed: een kant-en-klaar
/// transcript dat voorrang krijgt op eigen ASR (Podcasting 2.0).
class FeedTranscriptLink {
  const FeedTranscriptLink({
    required this.url,
    required this.type,
    this.language,
  });

  /// Opgelost tegen de feed-URL — nooit relatief.
  final Uri url;

  /// MIME-type zoals de feed het meldt (`text/vtt`, `text/plain`,
  /// `application/srt`, `application/json`…).
  final String type;

  /// Optionele `language`-aanduiding van de feed (BCP-47).
  final String? language;
}

/// Één aflevering met een afspeelbare enclosure. [key] is de stabiele
/// identiteit voor de wachtrij: de `guid`/`id` van de feed, met een
/// gedocumenteerde terugval — zie [fallbackEpisodeKey].
class FeedEpisode {
  const FeedEpisode({
    required this.key,
    required this.title,
    this.published,
    required this.enclosureUrl,
    required this.enclosureType,
    this.enclosureLength,
    this.transcripts = const [],
  });

  /// Stabiele sleutel binnen deze feed — hernoeming van titel of
  /// bijgewerkte enclosure-URL levert geen tweede aflevering.
  final String key;
  final String title;
  final DateTime? published;

  /// Opgelost tegen de feed-URL.
  final Uri enclosureUrl;

  /// MIME-type van de enclosure (`audio/mpeg`, `video/mp4`…).
  final String enclosureType;
  final int? enclosureLength;
  final List<FeedTranscriptLink> transcripts;
}

/// Wat de parser van één opgehaald document maakte. Alleen feeds met
/// minstens één media-aflevering komen hier terecht — een RSS zonder
/// enclosures is geen podcast en valt terug op de gewone openroute.
class PodcastFeed {
  const PodcastFeed({
    required this.sourceUrl,
    required this.title,
    this.siteUrl,
    required this.episodes,
  });

  /// De uiteindelijke URL waarop de feed is opgehaald (na omleidingen);
  /// relatieve verwijzingen zijn hiertegen opgelost.
  final Uri sourceUrl;
  final String title;
  final Uri? siteUrl;
  final List<FeedEpisode> episodes;
}

/// Sleutelterugval voor afleveringen zonder `guid`/`id`: de enclosure is
/// het sterkste resterende identiteitsanker, daarna de itemlink, daarna
/// titel+datum. Bewust geen hash over de hele iteminhoud — een comma in
/// de beschrijving zou dan een nieuwe aflevering "zijn".
String fallbackEpisodeKey({
  Uri? enclosureUrl,
  Uri? itemLink,
  String? title,
  DateTime? published,
}) {
  if (enclosureUrl != null) return 'enc:${enclosureUrl.toString()}';
  if (itemLink != null) return 'link:${itemLink.toString()}';
  return 'meta:${title ?? ''}|${published?.toIso8601String() ?? ''}';
}
