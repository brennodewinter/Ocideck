// Feedherkenning voor de URL-openroute (#2931): RSS en Atom in, een
// [PodcastFeed] of een lijst ontdekte feedlinks uit — nooit een worp.
//
// Bewust bytes→tekst→bomen, geen regex over XML: een `type`-attribuut
// dat liegt en een kapot document zijn beide gewone invoer. De Content-
// Type-header is alleen een aanwijzing van de router; híer telt de
// inhoud. Alles relatieve lost op tegen de uiteindelijke bron-URL.
import 'dart:convert';
import 'dart:typed_data';

import 'package:html/parser.dart' as html_parser;
import 'package:intl/intl.dart';
import 'package:xml/xml.dart';

import '../transcription/media_sniff.dart';
import 'feed_models.dart';

/// Wat de URL-inhoudsrouter met de opgehaalde bytes aanvangt.
enum UrlContentRoute {
  /// Een podcastfeed met minstens één media-aflevering.
  feed,

  /// Een HTML-pagina die zelf feedlinks aanmeldt — de gebruiker kiest
  /// of hij zo'n link wil openen.
  feedCandidates,

  /// Geen feed aangetoond — de gewone deck-/mediaroutes bepalen verder.
  notFeed,
}

class UrlContentVerdict {
  const UrlContentVerdict.feed(this.feed)
    : route = UrlContentRoute.feed,
      feedLinks = const [];
  const UrlContentVerdict.candidates(this.feedLinks)
    : route = UrlContentRoute.feedCandidates,
      feed = null;
  const UrlContentVerdict.notFeed()
    : route = UrlContentRoute.notFeed,
      feed = null,
      feedLinks = const [];

  final UrlContentRoute route;
  final PodcastFeed? feed;
  final List<Uri> feedLinks;
}

/// De router-ingang: classificeer opgehaalde bytes vóór de deck-parsing.
/// XML proberen is de herkenning; mislukt dat, kijken we of het HTML met
/// `link rel=alternate`-feeds is. Kapotte XML en vreemde tekst leveren
/// [UrlContentRoute.notFeed] — de aanroeper rapporteert zijn eigen,
/// eerlijkere reden.
UrlContentVerdict classifyUrlContent(Uint8List bytes, Uri sourceUrl) {
  final String text;
  try {
    text = utf8.decode(bytes, allowMalformed: true);
  } on Object {
    return const UrlContentVerdict.notFeed();
  }
  final head = text.trimLeft();
  if (!head.startsWith('<')) return const UrlContentVerdict.notFeed();

  if (_looksLikeHtml(head)) {
    final links = discoverFeedLinks(text, sourceUrl);
    return links.isEmpty
        ? const UrlContentVerdict.notFeed()
        : UrlContentVerdict.candidates(links);
  }

  final feed = parsePodcastFeed(text, sourceUrl);
  return feed == null
      ? const UrlContentVerdict.notFeed()
      : UrlContentVerdict.feed(feed);
}

/// `<html` of een DOCTYPE — RSS wordt ook weleens met een HTML-achtige
/// foutpagina geserveerd, maar die begint hier niet mee.
bool _looksLikeHtml(String head) {
  final lower = head.length > 200 ? head.substring(0, 200) : head;
  final l = lower.toLowerCase();
  return l.startsWith('<!doctype html') || l.startsWith('<html');
}

/// Parse één opgehaald document als podcastfeed. `null` bij geen XML,
/// geen feed-wortel, óf een feed zonder media-afleveringen — die laatste
/// is gewone syndicatie, geen podcast (#2931 herkent alleen feeds met
/// audio/video-enclosures).
PodcastFeed? parsePodcastFeed(String text, Uri sourceUrl) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(text);
  } on XmlException {
    return null;
  }
  final root = doc.rootElement;
  return switch (root.name.local) {
    'rss' => _parseRss(root, sourceUrl),
    'feed' => _parseAtom(root, sourceUrl),
    'RDF' => _parseRss(root, sourceUrl), // RSS 1.0: items naast channel
    _ => null,
  };
}

/// `link rel="alternate"`-feedverwijzingen uit een HTML-pagina —
/// opgelost tegen [baseUrl], alleen http(s).
List<Uri> discoverFeedLinks(String htmlText, Uri baseUrl) {
  final document = html_parser.parse(htmlText, sourceUrl: baseUrl.toString());
  final found = <Uri>{};
  for (final link in document.querySelectorAll('link')) {
    final rel = (link.attributes['rel'] ?? '').toLowerCase();
    final type = (link.attributes['type'] ?? '').toLowerCase();
    final href = link.attributes['href'];
    if (!rel.contains('alternate') || href == null) continue;
    if (type != 'application/rss+xml' && type != 'application/atom+xml') {
      continue;
    }
    final resolved = baseUrl.resolve(href);
    if (resolved.scheme == 'http' || resolved.scheme == 'https') {
      found.add(resolved);
    }
  }
  return found.toList(growable: false);
}

// ---------------------------------------------------------------------------
// RSS 2.0 (en RSS 1.0/RDF: zelfde itemvorm, andere wortel)
// ---------------------------------------------------------------------------

PodcastFeed? _parseRss(XmlElement root, Uri sourceUrl) {
  // RSS 1.0 zet <item> naast <channel>; RSS 2.0 erin. Beide pakken we via
  // findAllElements, maar channel-metadata alleen uit <channel> zelf.
  final channel = root.getElement('channel');
  final meta = channel ?? root;
  final title = meta.getElement('title')?.innerText.trim() ?? '';
  final site = _resolve(meta.getElement('link')?.innerText, sourceUrl);

  final items = root.findAllElements('item').toList(growable: false);
  final episodes = <FeedEpisode>[];
  final seen = <String>{};
  for (final item in items) {
    final enclosure = _rssEnclosure(item, sourceUrl);
    if (enclosure == null) continue;
    final guid = item.getElement('guid')?.innerText.trim();
    final link = _resolve(item.getElement('link')?.innerText, sourceUrl);
    final itemTitle = item.getElement('title')?.innerText.trim() ?? '';
    final published = _parseDate(
      item.getElement('pubDate')?.innerText ??
          item.getElement('date')?.innerText, // dc:date, lokale naam
    );
    final key = (guid != null && guid.isNotEmpty)
        ? guid
        : fallbackEpisodeKey(
            enclosureUrl: enclosure.url,
            itemLink: link,
            title: itemTitle,
            published: published,
          );
    if (!seen.add(key)) continue; // dubbele guid: eerste wint, geen dupe
    episodes.add(
      FeedEpisode(
        key: key,
        title: itemTitle,
        published: published,
        enclosureUrl: enclosure.url,
        enclosureType: enclosure.type,
        enclosureLength: enclosure.length,
        transcripts: _transcriptLinks(item, sourceUrl),
      ),
    );
  }
  if (episodes.isEmpty) return null;
  return PodcastFeed(
    sourceUrl: sourceUrl,
    title: title.isEmpty ? sourceUrl.host : title,
    siteUrl: site,
    episodes: episodes,
  );
}

/// De afspeelbare bron van een item: `<enclosure>` (standaard) of een
/// `<media:content>` met mediatype — sommige feeds kennen alleen die
/// laatste. `null` als geen van beide audio/video oplevert.
({Uri url, String type, int? length})? _rssEnclosure(
  XmlElement item,
  Uri sourceUrl,
) {
  ({Uri url, String type, int? length})? fromAttrs(
    String? urlAttr,
    String? typeAttr,
    String? lengthAttr,
  ) {
    final url = _resolve(urlAttr, sourceUrl);
    if (url == null) return null;
    final type = (typeAttr ?? '').toLowerCase();
    if (!_isMediaType(type, url)) return null;
    return (url: url, type: type, length: int.tryParse(lengthAttr ?? ''));
  }

  final enc = item.getElement('enclosure');
  final parsed = enc == null
      ? null
      : fromAttrs(
          enc.getAttribute('url'),
          enc.getAttribute('type'),
          enc.getAttribute('length'),
        );
  if (parsed != null) return parsed;
  // `media:content` heeft een voorvoegsel: zonder `'*'` vergelijkt
  // findAllElements de volledige naam en mist die.
  for (final el in item.findAllElements('content', namespaceUri: '*')) {
    final ns = el.name.namespaceUri ?? '';
    if (!ns.contains('mrss') && !ns.contains('media')) continue;
    final parsed2 = fromAttrs(
      el.getAttribute('url'),
      el.getAttribute('type'),
      el.getAttribute('fileSize'),
    );
    if (parsed2 != null) return parsed2;
  }
  return null;
}

/// `podcast:transcript`-verwijzingen van een item of entry. Alleen de
/// Podcasting-2.0-namespace telt — een toevallig gelijknamig element is
/// geen transcript.
List<FeedTranscriptLink> _transcriptLinks(XmlElement item, Uri sourceUrl) => [
  // `podcast:transcript` is voorvoegsel-namenrijk: `'*'` laat de lokale
  // naam matchen, de namespace-toets hieronder doet de echte selectie.
  for (final el in item.findAllElements('transcript', namespaceUri: '*'))
    if (el.name.namespaceUri?.contains('podcast') == true)
      if (_resolve(el.getAttribute('url'), sourceUrl) case final url?)
        FeedTranscriptLink(
          url: url,
          type: (el.getAttribute('type') ?? '').toLowerCase(),
          language: el.getAttribute('language'),
        ),
];

// ---------------------------------------------------------------------------
// Atom
// ---------------------------------------------------------------------------

PodcastFeed? _parseAtom(XmlElement root, Uri sourceUrl) {
  final title = root.getElement('title')?.innerText.trim() ?? '';
  final site = [
    for (final link in root.findElements('link'))
      if ((link.getAttribute('rel') ?? 'alternate') == 'alternate')
        _resolve(link.getAttribute('href'), sourceUrl),
  ].firstWhere((u) => u != null, orElse: () => null);

  final episodes = <FeedEpisode>[];
  final seen = <String>{};
  for (final entry in root.findElements('entry')) {
    Uri? enclosure;
    String enclosureType = '';
    Uri? alternate;
    for (final link in entry.findElements('link')) {
      final rel = link.getAttribute('rel') ?? 'alternate';
      final href = _resolve(link.getAttribute('href'), sourceUrl);
      if (href == null) continue;
      if (rel == 'enclosure' &&
          _isMediaType((link.getAttribute('type') ?? '').toLowerCase(), href)) {
        enclosure = href;
        enclosureType = (link.getAttribute('type') ?? '').toLowerCase();
      } else if (rel == 'alternate') {
        alternate ??= href;
      }
    }
    if (enclosure == null) continue;
    final id = entry.getElement('id')?.innerText.trim();
    final itemTitle = entry.getElement('title')?.innerText.trim() ?? '';
    final published = _parseDate(
      entry.getElement('published')?.innerText ??
          entry.getElement('updated')?.innerText,
    );
    final key = (id != null && id.isNotEmpty)
        ? id
        : fallbackEpisodeKey(
            enclosureUrl: enclosure,
            itemLink: alternate,
            title: itemTitle,
            published: published,
          );
    if (!seen.add(key)) continue;
    final length = [
      for (final link in entry.findElements('link'))
        if (link.getAttribute('rel') == 'enclosure' &&
            _resolve(link.getAttribute('href'), sourceUrl) == enclosure)
          int.tryParse(link.getAttribute('length') ?? ''),
    ].firstWhere((n) => n != null, orElse: () => null);
    episodes.add(
      FeedEpisode(
        key: key,
        title: itemTitle,
        published: published,
        enclosureUrl: enclosure,
        enclosureType: enclosureType,
        enclosureLength: length,
        transcripts: _transcriptLinks(entry, sourceUrl),
      ),
    );
  }
  if (episodes.isEmpty) return null;
  return PodcastFeed(
    sourceUrl: sourceUrl,
    title: title.isEmpty ? sourceUrl.host : title,
    siteUrl: site,
    episodes: episodes,
  );
}

// ---------------------------------------------------------------------------
// gedeeld
// ---------------------------------------------------------------------------

/// Lossen we op tegen [base]; alleen absolute http(s)-resultaten tellen —
/// een `feed:`-, `itpc:`- of javascript-href is geen ophaalbaar doel.
Uri? _resolve(String? href, Uri base) {
  if (href == null) return null;
  final trimmed = href.trim();
  if (trimmed.isEmpty) return null;
  final resolved = base.resolve(trimmed);
  if (resolved.scheme != 'http' && resolved.scheme != 'https') return null;
  return resolved;
}

/// Is deze enclosure een mediabron? Een expliciet audio-/video-type wint;
/// bij afwezig of generiek type beslist de extensie van de URL — feeds
/// vergeten het type regelmatig.
bool _isMediaType(String type, Uri url) {
  if (type.startsWith('audio/') || type.startsWith('video/')) return true;
  if (type.isNotEmpty && type != 'application/octet-stream') return false;
  final ext = url.path.split('.').last.toLowerCase();
  return mediaFileExtensions.contains(ext);
}

/// Datumstempels uit feeds zijn slordig: RFC-822 met weekdag, zonder
/// weekdag, met `GMT`, of gewoon ISO. Alles naar [DateTime] of `null` —
/// nooit de reden dat een aflevering verdwijnt.
DateTime? _parseDate(String? raw) {
  final text = raw?.trim();
  if (text == null || text.isEmpty) return null;
  final iso = DateTime.tryParse(text);
  if (iso != null) return iso;
  final normalized = text
      .replaceFirst(RegExp(r'(GMT|UT|UTC|Z)$'), '+0000')
      .replaceAll(RegExp(r'\s+'), ' ');
  for (final pattern in const [
    'EEE, dd MMM yyyy HH:mm:ss Z',
    'EEE, dd MMM yyyy HH:mm Z',
    'dd MMM yyyy HH:mm:ss Z',
  ]) {
    try {
      return DateFormat(pattern, 'en_US').parse(normalized, true);
    } on Object {
      // volgende patroon proberen
    }
  }
  return null;
}
