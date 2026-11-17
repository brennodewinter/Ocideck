// Abonnementen en controles voor podcastfeeds (#2931): de provider die
// de duurzame [FeedSubscription]-lijst beheert en de periodieke
// controle draait.
//
// Grenzen die hier bewaakt worden:
//  * Volgen is een expliciete keuze en hangt aan de AI-hoofdschakelaar —
//    AI uit pauzeert alle controles en verwerking (bestaande
//    abonnementen en documenten blijven staan).
//  * Pollen gebeurt bij opstarten en periodiek zolang de app draait;
//    een gesloten app of browsertab poll níét — dat is bewust en staat
//    zo in de uitleg.
//  * Elke controle is een conditionele GET (ETag/Last-Modified) met
//    back-off bij mislukkingen; nieuwe afleveringen landen als `fresh`
//    in de wachtrij, downloaden doet alleen `autoDownload` — een eigen
//    abonnementskeuze.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../services/feeds/feed_fetch.dart';
import '../services/feeds/feed_models.dart';
import '../services/feeds/feed_parser.dart';
import '../services/feeds/feed_store.dart';
import '../services/file_service.dart' show ImportFailure;
import 'settings_provider.dart';

/// Ophaalfunctie achter de controles — testbaar maakbaar zonder het
/// netwerk, het retourtype blijft het echte contract.
typedef FeedFetcher =
    Future<FeedFetchResult> Function(
      Uri url, {
      String? etag,
      String? lastModified,
    });

/// Klokinjectie voor tests; productie gebruikt DateTime.now.
typedef FeedClock = DateTime Function();

/// Past één opgehaalde feed toe op een abonnement: nieuwe afleveringen
/// komen als `fresh` erbij, bestaande blijven staan (titel- en URL-
/// wijzigingen dedupen op sleutel). Geeft de nieuw binnengekomen
/// records terug. Pure logica, geen IO — apart van de notifier zodat de
/// diff- en dedupregels direct testbaar zijn.
List<FeedEpisodeRecord> applyFeedToSubscription(
  FeedSubscription sub,
  PodcastFeed feed,
) {
  sub.resolvedUrl = feed.sourceUrl;
  if (feed.title.isNotEmpty) sub.title = feed.title;
  final added = <FeedEpisodeRecord>[];
  for (final ep in feed.episodes) {
    if (sub.episodes.containsKey(ep.key)) continue;
    final record = FeedEpisodeRecord(
      key: ep.key,
      title: ep.title,
      published: ep.published,
      enclosureUrl: ep.enclosureUrl,
      enclosureType: ep.enclosureType,
      transcripts: ep.transcripts,
      status: FeedEpisodeStatus.fresh,
    );
    sub.episodes[ep.key] = record;
    added.add(record);
  }
  return added;
}

/// Een nieuw abonnement zaait zijn huidige afleveringen als `seen`:
/// volgen markeert vanaf nu nieuwe items, geen rugwacht van honderden
/// "nieuwe" afleveringen.
FeedSubscription subscriptionFromFeed(
  PodcastFeed feed,
  Uri requestedUrl,
  Duration interval,
) {
  final sub = FeedSubscription(
    feedUrl: requestedUrl,
    resolvedUrl: feed.sourceUrl,
    title: feed.title,
    checkInterval: interval,
  );
  for (final ep in feed.episodes) {
    sub.episodes[ep.key] = FeedEpisodeRecord(
      key: ep.key,
      title: ep.title,
      published: ep.published,
      enclosureUrl: ep.enclosureUrl,
      enclosureType: ep.enclosureType,
      transcripts: ep.transcripts,
    );
  }
  return sub;
}

/// Beheert de abonnementenlijst en de controlecyclus.
class FeedStoreNotifier extends Notifier<List<FeedSubscription>> {
  static const _prefsKey = FeedStoreCodec.prefsKey;
  static const _tick = Duration(minutes: 1);

  /// Interval-opties die de volgdialoog aanbiedt (in minuten).
  static const intervalChoices = <Duration>[
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 6),
    Duration(hours: 24),
  ];

  /// Bovengrens voor automatische downloads — bewust ruim onder de
  /// handmatige medialimiet: een abonnement mag geen onbeperkte stroom
  /// starten zonder dat er iemand bij is.
  static const autoDownloadMaxBytes = 512 * 1024 * 1024;

  final _codec = const FeedStoreCodec();
  Timer? _timer;
  SharedPreferences? _prefs;
  bool _loaded = false;
  final _uuid = const Uuid();

  /// Testhaken: netwerk en klok zijn vervangbaar vóór [load] klaar is.
  FeedFetcher fetcher = _defaultFetch;
  FeedClock clock = DateTime.now;

  static Future<FeedFetchResult> _defaultFetch(
    Uri url, {
    String? etag,
    String? lastModified,
  }) => fetchFeed(url, etag: etag, lastModified: lastModified);

  @override
  List<FeedSubscription> build() {
    _timer ??= Timer.periodic(_tick, (_) => unawaited(_checkDue()));
    ref.onDispose(() => _timer?.cancel());
    unawaited(_load());
    return const [];
  }

  bool get _aiEnabled => ref.read(settingsProvider).aiSettings.enabled;

  Future<void> _load() async {
    _prefs ??= await SharedPreferences.getInstance();
    if (!ref.mounted) return;
    state = _codec.decode(_prefs!.getString(_prefsKey));
    _loaded = true;
    // Opstartcontrole: wie al voorbij zijn interval was, controleert nu.
    unawaited(_checkDue());
  }

  Future<void> _persist() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_prefsKey, _codec.encode(state));
  }

  /// Volg [feed] met gekozen [interval]. Al aanwezig (op feed- of
  /// eindadres) telt als dezelfde feed en geeft `false` — de dialoog
  /// kan dan "wordt al gevolgd" tonen in plaats van een duplicaat.
  Future<bool> follow(
    PodcastFeed feed,
    Uri requestedUrl,
    Duration interval,
  ) async {
    final exists = state.any(
      (s) => s.feedUrl == requestedUrl || s.resolvedUrl == feed.sourceUrl,
    );
    if (exists) return false;
    state = [...state, subscriptionFromFeed(feed, requestedUrl, interval)];
    await _persist();
    return true;
  }

  FeedSubscription? _find(Uri feedUrl) {
    for (final sub in state) {
      if (sub.feedUrl == feedUrl || sub.resolvedUrl == feedUrl) return sub;
    }
    return null;
  }

  FeedSubscription? subscriptionFor(Uri feedUrl) => _find(feedUrl);

  Future<void> unfollow(Uri feedUrl) async {
    state = state.where((s) => _find(feedUrl) != s).toList();
    await _persist();
  }

  Future<void> setPaused(Uri feedUrl, bool paused) async {
    final sub = _find(feedUrl);
    if (sub == null) return;
    sub.paused = paused;
    state = [...state];
    await _persist();
  }

  Future<void> setAutoDownload(Uri feedUrl, bool enabled) async {
    final sub = _find(feedUrl);
    if (sub == null) return;
    sub.autoDownload = enabled;
    state = [...state];
    await _persist();
  }

  Future<void> markEpisode(
    Uri feedUrl,
    String episodeKey,
    FeedEpisodeStatus status,
  ) async {
    final ep = _find(feedUrl)?.episodes[episodeKey];
    if (ep == null) return;
    ep.status = status;
    state = [...state];
    await _persist();
  }

  /// Onthoud het sessie-pad van een opgehaalde enclosure — vluchtig,
  /// dus geen persist nodig (zie het veldcommentaar in de store).
  void noteDownloadedPath(Uri feedUrl, String episodeKey, String path) {
    final ep = _find(feedUrl)?.episodes[episodeKey];
    if (ep == null) return;
    ep.downloadedPath = path;
    state = [...state];
  }

  /// Controleer alles wat nu aan de beurt is. `force` slaat de interval-
  /// toets over (Nu vernieuwen). AI uit betekent: geen controles, geen
  /// verwerking — de opslag blijft ongemoeid staan.
  Future<void> _checkDue({bool force = false}) async {
    if (!_loaded || !_aiEnabled) return;
    final now = clock();
    for (final sub in List.of(state)) {
      if (sub.paused) continue;
      if (!force && (sub.nextCheck?.isAfter(now) ?? false)) continue;
      await _check(sub, now);
    }
  }

  /// Handmatige verversing vanuit de dialoog. Geeft het aantal nieuwe
  /// afleveringen, of gooit de [ImportFailure] zodat de schil dezelfde
  /// gerichte melding kan tonen als de importroute.
  Future<int> refreshNow(Uri feedUrl) async {
    final sub = _find(feedUrl);
    if (sub == null) return 0;
    final result = await _check(sub, clock());
    if (result != null) throw result;
    return sub.freshCount;
  }

  /// Eén controle van [sub]; geeft de falende reden terug of null.
  Future<ImportFailure?> _check(FeedSubscription sub, DateTime now) async {
    final result = await fetcher(
      sub.resolvedUrl,
      etag: sub.etag,
      lastModified: sub.lastModified,
    );
    // De controle kan de provider overleven (dispone tijdens een poll):
    // state-aanraking na een await vraagt de mounted-toets.
    if (!ref.mounted) return null;
    if (result.failure != null) {
      sub.consecutiveFailures += 1;
      sub.lastChecked = now;
      state = [...state];
      await _persist();
      return result.failure;
    }
    sub.consecutiveFailures = 0;
    sub.lastChecked = now;
    if (result.notModified) {
      state = [...state];
      await _persist();
      return null;
    }
    final feed = parsePodcastFeed(
      utf8.decode(result.bytes!, allowMalformed: true),
      result.finalUrl ?? sub.resolvedUrl,
    );
    if (feed == null) {
      // Een 200 die geen feed meer is telt als mislukte controle:
      // de bron is weg of stuk, de back-off voorkomt stampvolle polls.
      sub.consecutiveFailures += 1;
      state = [...state];
      await _persist();
      return ImportFailure.corrupt;
    }
    sub.etag = result.etag ?? sub.etag;
    sub.lastModified = result.lastModified ?? sub.lastModified;
    final added = applyFeedToSubscription(sub, feed);
    state = [...state];
    await _persist();
    for (final ep in added) {
      unawaited(_maybeAutoDownload(sub, ep));
    }
    return null;
  }

  /// Automatisch downloaden is de afzonderlijke abonnementskeuze:
  /// de enclosure gaat naar staging en blijft `fresh` — transcriberen
  /// blijft een handmatige, zichtbare stap. Op web is er geen
  /// stagingbestand; daar blijft automatisch downloaden uit.
  Future<void> _maybeAutoDownload(
    FeedSubscription sub,
    FeedEpisodeRecord ep,
  ) async {
    if (!sub.autoDownload || kIsWeb || !ref.mounted) return;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/ocideck-feed-${_uuid.v4()}.bin';
    final outcome = await downloadFeedMedia(
      ep.enclosureUrl,
      path,
      maxBytes: autoDownloadMaxBytes,
    );
    if (!ref.mounted || outcome.path == null) return;
    noteDownloadedPath(sub.feedUrl, ep.key, outcome.path!);
  }
}

/// De abonnementen met hun afleveringswachtrij.
final feedStoreProvider =
    NotifierProvider<FeedStoreNotifier, List<FeedSubscription>>(
      FeedStoreNotifier.new,
    );

/// Totaal aantal afleveringen dat als nieuw in de wachtrij staat — de
/// badge in het menu en de trigger voor de aankondiging.
final feedFreshCountProvider = Provider<int>((ref) {
  var count = 0;
  for (final sub in ref.watch(feedStoreProvider)) {
    count += sub.freshCount;
  }
  return count;
});
