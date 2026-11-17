// Tests voor de podcastfeed-keten (#2931): herkenning (RSS/Atom/HTML-
// discovery, kapotte invoer, verkeerde aanduidingen), de duurzame store
// (codec, dedupe, back-off) en de providercyclus (volgen, 304, nieuwe
// afleveringen, herstart). Netwerk zit achter de injecteerbare fetcher —
// er gaat geen echte byte de lijn op.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ai_settings.dart';
import 'package:ocideck/services/feeds/feed_fetch.dart';
import 'package:ocideck/services/feeds/feed_models.dart';
import 'package:ocideck/services/feeds/feed_parser.dart';
import 'package:ocideck/services/feeds/feed_store.dart';
import 'package:ocideck/services/feeds/feed_transcript.dart';
import 'package:ocideck/services/file_service.dart' show ImportFailure;
import 'package:ocideck/state/feed_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const rssFeed = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:podcast="https://podcastindex.org/namespace/1.0">
  <channel>
    <title>Voorbeeldpodcast</title>
    <link>https://example.com/show</link>
    <item>
      <title>Aflevering één</title>
      <guid>ep-001</guid>
      <pubDate>Mon, 06 Jan 2025 10:00:00 GMT</pubDate>
      <enclosure url="media/ep1.mp3" type="audio/mpeg" length="1234"/>
      <podcast:transcript url="transcripts/ep1.vtt" type="text/vtt" language="nl"/>
    </item>
    <item>
      <title>Aflevering twee</title>
      <guid>ep-002</guid>
      <enclosure url="https://cdn.example.com/ep2.mp4" type="video/mp4"/>
    </item>
  </channel>
</rss>
''';

const atomFeed = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atomshow</title>
  <link href="https://example.org/atom-show" rel="alternate"/>
  <entry>
    <id>urn:episode:1</id>
    <title>Eerste atom-aflevering</title>
    <published>2025-02-01T12:00:00Z</published>
    <link href="ep/a1" rel="alternate"/>
    <link href="../audio/a1.m4a" rel="enclosure" type="audio/mp4" length="42"/>
  </entry>
</feed>
''';

final feedUri = Uri.parse('https://example.com/feeds/podcast.xml');

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('parsePodcastFeed', () {
    test('RSS: titel, site, afleveringen en relatieve URLs', () {
      final feed = parsePodcastFeed(rssFeed, feedUri)!;
      expect(feed.title, 'Voorbeeldpodcast');
      expect(feed.siteUrl, Uri.parse('https://example.com/show'));
      expect(feed.episodes, hasLength(2));
      final ep1 = feed.episodes.first;
      expect(ep1.key, 'ep-001');
      // Relatieve enclosure lost op tegen de feed-URL.
      expect(
        ep1.enclosureUrl,
        Uri.parse('https://example.com/feeds/media/ep1.mp3'),
      );
      expect(ep1.enclosureType, 'audio/mpeg');
      expect(ep1.enclosureLength, 1234);
      expect(ep1.published, isNotNull);
      expect(ep1.transcripts.single.type, 'text/vtt');
      expect(
        ep1.transcripts.single.url,
        Uri.parse('https://example.com/feeds/transcripts/ep1.vtt'),
      );
    });

    test('Atom: rel=enclosure wordt de media-en id de sleutel', () {
      final feed = parsePodcastFeed(
        atomFeed,
        Uri.parse('https://example.org/dir/feed.atom'),
      )!;
      expect(feed.title, 'Atomshow');
      final ep = feed.episodes.single;
      expect(ep.key, 'urn:episode:1');
      // `../audio` t.o.v. /dir/feed.atom → /audio/a1.m4a.
      expect(ep.enclosureUrl, Uri.parse('https://example.org/audio/a1.m4a'));
      expect(ep.enclosureType, 'audio/mp4');
    });

    test('RSS zonder enclosures is géén podcast', () {
      const text =
          '<rss version="2.0"><channel><title>Nieuws</title>'
          '<item><title>Stuk</title><link>https://x.test/a</link></item>'
          '</channel></rss>';
      expect(parsePodcastFeed(text, feedUri), isNull);
    });

    test('kapotte XML en niet-XML geven null', () {
      expect(parsePodcastFeed('<rss><channel><title>', feedUri), isNull);
      expect(parsePodcastFeed('gewoon een lap tekst', feedUri), isNull);
      expect(parsePodcastFeed('{"json": true}', feedUri), isNull);
    });

    test('dubbele guid levert één aflevering', () {
      const text =
          '<rss version="2.0"><channel><title>x</title>'
          '<item><title>a</title><guid>dezelfde</guid>'
          '<enclosure url="https://x.test/1.mp3" type="audio/mpeg"/></item>'
          '<item><title>b</title><guid>dezelfde</guid>'
          '<enclosure url="https://x.test/2.mp3" type="audio/mpeg"/></item>'
          '</channel></rss>';
      final feed = parsePodcastFeed(text, feedUri)!;
      expect(feed.episodes.single.title, 'a'); // de eerste wint
    });

    test('media:content zonder <enclosure> telt ook', () {
      const text =
          '<rss version="2.0" '
          'xmlns:media="http://search.yahoo.com/mrss/">'
          '<channel><title>x</title><item><title>m</title><guid>g1</guid>'
          '<media:content url="https://x.test/m.mp3" type="audio/mpeg"/>'
          '</item></channel></rss>';
      final feed = parsePodcastFeed(text, feedUri)!;
      expect(feed.episodes.single.enclosureUrl.host, 'x.test');
    });

    test('type-loze enclosure valt terug op de extensie', () {
      const text =
          '<rss version="2.0"><channel><title>x</title>'
          '<item><title>a</title><guid>g</guid>'
          '<enclosure url="https://x.test/audio.mp3"/></item>'
          '<item><title>b</title><guid>g2</guid>'
          '<enclosure url="https://x.test/pagina"/></item>'
          '</channel></rss>';
      final feed = parsePodcastFeed(text, feedUri)!;
      expect(feed.episodes, hasLength(1)); // alleen de herkenbare media
    });
  });

  group('classifyUrlContent', () {
    test('feedbytes route als feed, ongeacht hoe de server ze noemde', () {
      final verdict = classifyUrlContent(_bytes(rssFeed), feedUri);
      expect(verdict.route, UrlContentRoute.feed);
      expect(verdict.feed!.episodes, hasLength(2));
    });

    test('HTML met link rel=alternate levert kandidaten op', () {
      const html =
          '<!doctype html><html><head>'
          '<link rel="alternate" type="application/rss+xml" href="/feed.xml">'
          '<link rel="stylesheet" href="/x.css">'
          '</head><body>podcastsite</body></html>';
      final verdict = classifyUrlContent(
        _bytes(html),
        Uri.parse('https://example.com/show'),
      );
      expect(verdict.route, UrlContentRoute.feedCandidates);
      expect(
        verdict.feedLinks.single,
        Uri.parse('https://example.com/feed.xml'),
      );
    });

    test('HTML zónder feedlink en ziplijm zijn geen feed', () {
      expect(
        classifyUrlContent(
          _bytes('<html><body>niks</body></html>'),
          feedUri,
        ).route,
        UrlContentRoute.notFeed,
      );
      // Zip-magie (een .ocideck-pakket) mag de feedroute niet happeren.
      expect(
        classifyUrlContent(
          Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 1, 2, 3]),
          feedUri,
        ).route,
        UrlContentRoute.notFeed,
      );
    });
  });

  group('fallbackEpisodeKey', () {
    test('enclosure wint op link, link wint op meta', () {
      final enc = Uri.parse('https://x.test/e.mp3');
      final link = Uri.parse('https://x.test/item');
      expect(
        fallbackEpisodeKey(enclosureUrl: enc, itemLink: link, title: 't'),
        'enc:https://x.test/e.mp3',
      );
      expect(
        fallbackEpisodeKey(itemLink: link, title: 't'),
        'link:https://x.test/item',
      );
      expect(fallbackEpisodeKey(title: 't'), startsWith('meta:t|'));
    });
  });

  group('FeedStoreCodec', () {
    const codec = FeedStoreCodec();

    test('ronde rit bewaart abonnement en afleveringsstatus', () {
      final sub = FeedSubscription(
        feedUrl: feedUri,
        resolvedUrl: feedUri,
        title: 'Voorbeeldpodcast',
        checkInterval: const Duration(hours: 1),
        etag: '"v1"',
        lastModified: 'Mon, 06 Jan 2025 00:00:00 GMT',
        lastChecked: DateTime.utc(2025, 1, 6, 12),
        consecutiveFailures: 2,
        paused: true,
        episodes: {
          'ep-001': FeedEpisodeRecord(
            key: 'ep-001',
            title: 'Aflevering één',
            enclosureUrl: Uri.parse('https://x.test/1.mp3'),
            enclosureType: 'audio/mpeg',
            status: FeedEpisodeStatus.fresh,
          ),
        },
      );
      final back = codec.decode(codec.encode([sub])).single;
      expect(back.feedUrl, feedUri);
      expect(back.etag, '"v1"');
      expect(back.paused, isTrue);
      expect(back.consecutiveFailures, 2);
      expect(back.episodes['ep-001']!.status, FeedEpisodeStatus.fresh);
    });

    test('kapotte of lege opslag levert een lege lijst', () {
      expect(codec.decode(null), isEmpty);
      expect(codec.decode('{geen json'), isEmpty);
      expect(codec.decode('["geen map"]'), isEmpty);
    });
  });

  group('back-off', () {
    test('mislukkingen verdubbelen het interval tot een dag', () {
      final sub = FeedSubscription(
        feedUrl: feedUri,
        resolvedUrl: feedUri,
        title: 'x',
        checkInterval: const Duration(minutes: 15),
        consecutiveFailures: 3,
      );
      expect(sub.effectiveInterval, const Duration(hours: 2));
      sub.consecutiveFailures = 20;
      expect(sub.effectiveInterval, const Duration(hours: 24));
    });
  });

  group('transcriptovername', () {
    const vtt = '''
WEBVTT

00:00:01.000 --> 00:00:03.000
<v Spreker>Hallo allemaal</v>

00:00:03.500 --> 00:00:05.000
Dit is een tweede zin.
''';

    test('VTT levert segmenten met tijdstempels', () {
      final segments = parseVtt(vtt);
      expect(segments, hasLength(2));
      expect(segments.first.text, 'Hallo allemaal');
      expect(segments.first.start, const Duration(seconds: 1));
      expect(segments.first.end, const Duration(seconds: 3));
    });

    test('transcriptdocument draagt provenance mee', () {
      final md = episodeTranscriptMarkdown(
        text: vtt,
        link: FeedTranscriptLink(
          url: Uri.parse('https://x.test/t.vtt'),
          type: 'text/vtt',
          language: 'nl',
        ),
        feedTitle: 'Voorbeeldpodcast',
        episodeTitle: 'Aflevering één',
        fetchedAtLabel: '6 januari 2025',
      )!;
      expect(md, contains('Aflevering één'));
      expect(md, contains('Hallo allemaal'));
      expect(md, contains('https://x.test/t.vtt'));
    });

    test('lege inhoud is eerlijk null', () {
      expect(
        episodeTranscriptMarkdown(
          text: 'WEBVTT\n\n',
          link: FeedTranscriptLink(
            url: Uri.parse('https://x.test/t.vtt'),
            type: 'text/vtt',
          ),
          feedTitle: 'x',
          episodeTitle: 'y',
          fetchedAtLabel: 'nu',
        ),
        isNull,
      );
    });
  });

  group('FeedStoreNotifier', () {
    const interval = Duration(hours: 1);

    Future<FeedStoreNotifier> versProvider(ProviderContainer c) async {
      // AI-hoofdschakelaar aan: zonder die pauzeert de hele cyclus.
      await c
          .read(settingsProvider.notifier)
          .setAiSettings(const AiSettings(enabled: true));
      final notifier = c.read(feedStoreProvider.notifier);
      c.read(feedStoreProvider); // build + _load starten
      await pumpEventQueue();
      return notifier;
    }

    test(
      'volgen zaait bestaande afleveringen als gezien, niet als nieuw',
      () async {
        SharedPreferences.setMockInitialValues({});
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final notifier = await versProvider(c);
        final feed = parsePodcastFeed(rssFeed, feedUri)!;

        expect(await notifier.follow(feed, feedUri, interval), isTrue);
        final sub = c.read(feedStoreProvider).single;
        expect(sub.episodes, hasLength(2));
        expect(sub.freshCount, 0); // rugwacht telt niet als nieuw

        // Dezelfde bron opnieuw volgen is geen tweede abonnement.
        expect(await notifier.follow(feed, feedUri, interval), isFalse);
      },
    );

    test('controle met nieuwe aflevering zet hem in de wachtrij', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final notifier = await versProvider(c);
      final feed = parsePodcastFeed(rssFeed, feedUri)!;
      await notifier.follow(feed, feedUri, interval);

      const updated = '''
<rss version="2.0"><channel><title>Voorbeeldpodcast</title>
  <item><title>Aflevering drie</title><guid>ep-003</guid>
    <enclosure url="https://cdn.example.com/ep3.mp3" type="audio/mpeg"/></item>
</channel></rss>
''';
      notifier.fetcher = (url, {etag, lastModified}) async {
        return FeedFetchResult.ok(
          statusCode: 200,
          bytes: _bytes(updated),
          etag: '"v2"',
          finalUrl: url,
        );
      };
      expect(await notifier.refreshNow(feedUri), 1);
      final sub = c.read(feedStoreProvider).single;
      expect(sub.etag, '"v2"');
      final rec = sub.episodes['ep-003']!;
      expect(rec.status, FeedEpisodeStatus.fresh);
    });

    test('304 laat alles staan maar telt als gecontroleerd', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final notifier = await versProvider(c);
      notifier.clock = () => DateTime.utc(2025, 1, 6, 12);
      final feed = parsePodcastFeed(rssFeed, feedUri)!;
      await notifier.follow(feed, feedUri, interval);

      notifier.fetcher = (url, {etag, lastModified}) async =>
          FeedFetchResult.ok(statusCode: 304, finalUrl: url);
      expect(await notifier.refreshNow(feedUri), 0);
      final sub = c.read(feedStoreProvider).single;
      expect(sub.freshCount, 0);
      expect(sub.lastChecked, DateTime.utc(2025, 1, 6, 12));
    });

    test(
      'mislukte controle telt mee in de back-off en gooit bij refresh',
      () async {
        SharedPreferences.setMockInitialValues({});
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final notifier = await versProvider(c);
        final feed = parsePodcastFeed(rssFeed, feedUri)!;
        await notifier.follow(feed, feedUri, interval);

        notifier.fetcher = (url, {etag, lastModified}) async =>
            const FeedFetchResult.failed(ImportFailure.network);
        await expectLater(
          notifier.refreshNow(feedUri),
          throwsA(ImportFailure.network),
        );
        final sub = c.read(feedStoreProvider).single;
        expect(sub.consecutiveFailures, 1);
        expect(sub.effectiveInterval, const Duration(hours: 2));
      },
    );

    test('status en abonnementen overleven een "herstart"', () async {
      SharedPreferences.setMockInitialValues({});
      final c1 = ProviderContainer();
      final notifier = await versProvider(c1);
      final feed = parsePodcastFeed(rssFeed, feedUri)!;
      await notifier.follow(feed, feedUri, interval);
      await notifier.markEpisode(feedUri, 'ep-001', FeedEpisodeStatus.handled);
      c1.dispose();

      // Tweede container, zelfde (gemockte) prefs: de opslag spreekt.
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      await versProvider(c2);
      final sub = c2.read(feedStoreProvider).single;
      expect(sub.title, 'Voorbeeldpodcast');
      expect(sub.episodes['ep-001']!.status, FeedEpisodeStatus.handled);
      expect(sub.episodes['ep-002']!.status, FeedEpisodeStatus.seen);
    });

    test('stoppen ruimt het abonnement op', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final notifier = await versProvider(c);
      final feed = parsePodcastFeed(rssFeed, feedUri)!;
      await notifier.follow(feed, feedUri, interval);
      await notifier.unfollow(feedUri);
      expect(c.read(feedStoreProvider), isEmpty);
    });
  });
}
