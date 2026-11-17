// De feeddialoog achter Openen via URL (#2931): een opgehaalde URL die
// een podcastfeed blijkt krijgt zijn eigen venster — titel, bron en
// afleveringen, met per aflevering dezelfde acties als de wachtrij.
// Volgen is een expliciete keuze en hangt aan de AI-hoofdschakelaar.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../services/feeds/feed_models.dart';
import '../../services/feeds/feed_store.dart';
import '../../services/feeds/feed_transcript.dart';
import '../../state/feed_provider.dart';
import '../../state/settings_provider.dart';
import '../../theme/app_theme.dart';
import 'feed_episode_actions.dart';

/// Toon een herkende podcastfeed. [requestedUrl] is wat de gebruiker
/// zelf intikte (en waarmee een abonnement zich identificeert);
/// [feed.sourceUrl] is het eindadres na omleidingen.
Future<void> showPodcastFeedDialog(
  BuildContext context,
  PodcastFeed feed,
  Uri requestedUrl,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _PodcastFeedDialog(feed: feed, requestedUrl: requestedUrl),
  );
}

/// Keuze tussen `link rel=alternate`-feeds uit een HTML-pagina. Geeft de
/// gekozen feed-URL terug, of null bij afwijzen.
Future<Uri?> showFeedLinkChoiceDialog(
  BuildContext context,
  List<Uri> feedLinks,
) {
  return showDialog<Uri>(
    context: context,
    builder: (_) => _FeedLinkChoiceDialog(feedLinks: feedLinks),
  );
}

class _PodcastFeedDialog extends ConsumerStatefulWidget {
  const _PodcastFeedDialog({required this.feed, required this.requestedUrl});

  final PodcastFeed feed;
  final Uri requestedUrl;

  @override
  ConsumerState<_PodcastFeedDialog> createState() => _PodcastFeedDialogState();
}

class _PodcastFeedDialogState extends ConsumerState<_PodcastFeedDialog> {
  Duration _interval = const Duration(hours: 1);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final feed = widget.feed;
    final aiEnabled = ref.watch(
      settingsProvider.select((s) => s.aiSettings.enabled),
    );
    final followed = ref
        .watch(feedStoreProvider)
        .any(
          (s) =>
              s.feedUrl == widget.requestedUrl ||
              s.resolvedUrl == feed.sourceUrl,
        );
    final episodes = feed.episodes.take(100).toList();
    return AlertDialog(
      title: Text(feed.title),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${feed.sourceUrl.host} · '
              '${l10n.d('afleveringen')}: ${feed.episodes.length}',
              style: TextStyle(fontSize: 12, color: AppTheme.slate500),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: episodes.length,
                itemBuilder: (_, i) => _episodeTile(
                  context,
                  ref,
                  episodes[i],
                  feedUrl: widget.requestedUrl,
                  feedTitle: feed.title,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (followed)
              Text(
                l10n.d('Deze feed wordt gevolgd.'),
                style: TextStyle(fontSize: 12, color: AppTheme.slate600),
              )
            else if (aiEnabled)
              Row(
                children: [
                  DropdownButton<Duration>(
                    value: _interval,
                    items: [
                      for (final d in FeedStoreNotifier.intervalChoices)
                        DropdownMenuItem(
                          value: d,
                          child: Text(_intervalLabel(l10n, d)),
                        ),
                    ],
                    onChanged: (v) =>
                        setState(() => _interval = v ?? _interval),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.playlist_add, size: 18),
                    label: Text(l10n.d('Feed volgen')),
                    onPressed: () => _follow(context),
                  ),
                ],
              )
            else
              Text(
                l10n.d('Zet AI aan in de instellingen om deze feed te volgen.'),
                style: TextStyle(fontSize: 12, color: AppTheme.slate500),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Sluiten')),
        ),
      ],
    );
  }

  Future<void> _follow(BuildContext context) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final added = await ref
        .read(feedStoreProvider.notifier)
        .follow(widget.feed, widget.requestedUrl, _interval);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          added
              ? l10n.d('Deze feed wordt gevolgd.')
              : l10n.d('Deze feed stond al in de lijst.'),
        ),
      ),
    );
  }
}

/// Eén afleveringsregel — gedeelde vorm voor herkende feeds én de
/// wachtrij in de abonnementendialoog. [record] kan ook een vers geparste
/// aflevering zijn; `key`/`enclosure` liggen dan al vast.
Widget _episodeTile(
  BuildContext context,
  WidgetRef ref,
  FeedEpisode episode, {
  required Uri feedUrl,
  required String feedTitle,
  FeedEpisodeStatus? queueStatus,
}) {
  final l10n = context.l10n;
  final record = FeedEpisodeRecord(
    key: episode.key,
    title: episode.title,
    published: episode.published,
    enclosureUrl: episode.enclosureUrl,
    enclosureType: episode.enclosureType,
    transcripts: episode.transcripts,
  );
  final usableTranscript = episode.transcripts
      .where(transcriptLinkUsable)
      .firstOrNull;
  final date = episode.published == null
      ? ''
      : DateFormat('yyyy-MM-dd').format(episode.published!);
  return ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(
      episode.title.isEmpty ? episode.enclosureUrl.path : episode.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13),
    ),
    subtitle: Text(
      [
        if (date.isNotEmpty) date,
        episode.enclosureType,
      ].where((s) => s.isNotEmpty).join(' · '),
      style: TextStyle(fontSize: 11, color: AppTheme.slate500),
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (usableTranscript != null)
          IconButton(
            icon: const Icon(Icons.article_outlined, size: 18),
            tooltip: l10n.d('Transcript ophalen'),
            onPressed: () => fetchEpisodeTranscript(
              context,
              ref,
              feedUrl: feedUrl,
              feedTitle: feedTitle,
              episode: record,
              link: usableTranscript,
            ),
          ),
        IconButton(
          icon: const Icon(Icons.graphic_eq_outlined, size: 18),
          tooltip: l10n.d('Transcriberen…'),
          onPressed: () => transcribeFeedEpisode(
            context,
            ref,
            feedUrl: feedUrl,
            feedTitle: feedTitle,
            episode: record,
          ),
        ),
        if (queueStatus != null)
          IconButton(
            icon: const Icon(Icons.check_outlined, size: 18),
            tooltip: l10n.d('Markeren als verwerkt'),
            onPressed: () => ref
                .read(feedStoreProvider.notifier)
                .markEpisode(feedUrl, episode.key, FeedEpisodeStatus.handled),
          ),
      ],
    ),
  );
}

/// Gedeelde tegel voor de wachtrij: een [FeedEpisodeRecord] uit een
/// abonnement, met extra markeer-knop.
Widget feedQueueEpisodeTile(
  BuildContext context,
  WidgetRef ref,
  FeedEpisodeRecord record, {
  required Uri feedUrl,
  required String feedTitle,
}) {
  return _episodeTile(
    context,
    ref,
    FeedEpisode(
      key: record.key,
      title: record.title,
      published: record.published,
      enclosureUrl: record.enclosureUrl,
      enclosureType: record.enclosureType,
      transcripts: record.transcripts,
    ),
    feedUrl: feedUrl,
    feedTitle: feedTitle,
    queueStatus: record.status,
  );
}

/// Letterlijke labels per keuze — geen geïnterpoleerde `d()`-sleutels:
/// de lokalisatie-index werkt alleen met vaste bronteksten.
String _intervalLabel(AppLocalizations l10n, Duration d) => switch (d) {
  const Duration(minutes: 15) => l10n.d('Elke 15 minuten'),
  const Duration(minutes: 30) => l10n.d('Elke 30 minuten'),
  const Duration(hours: 1) => l10n.d('Elk uur'),
  const Duration(hours: 6) => l10n.d('Elke 6 uur'),
  _ => l10n.d('Dagelijks'),
};

class _FeedLinkChoiceDialog extends StatelessWidget {
  const _FeedLinkChoiceDialog({required this.feedLinks});

  final List<Uri> feedLinks;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Feed gevonden')),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d('Deze pagina biedt geen presentatie, maar wel een feed:'),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            const SizedBox(height: 8),
            for (final link in feedLinks)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.rss_feed, size: 18),
                title: Text(
                  link.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () => Navigator.of(context).pop(link),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Annuleren')),
        ),
      ],
    );
  }
}
