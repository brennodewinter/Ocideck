// De twee afleveringsacties die de feeddialoog en de wachtrij delen
// (#2931): audio ophalen en naar de bestaande transcriptievoorbeschouwing,
// of een aangeboden `podcast:transcript` direct als document openen.
//
// Beide gaan door dezelfde netwerkgrenzen als de feedcontrole zelf
// (NetGuard-pin op desktop, CORS op web, eigen omvangslimieten) en
// melden een mislukking met dezelfde gerichte teksten als de URL-import.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/app_localizations.dart';
import '../../platform/platform_features.dart';
import '../../services/feeds/feed_fetch.dart';
import '../../services/feeds/feed_models.dart';
import '../../services/feeds/feed_store.dart';
import '../../services/feeds/feed_transcript.dart';
import '../../services/file_service.dart' show ImportFailure;
import '../../services/transcription/file_capture_source.dart'
    show maxFileSourceBytes;
import '../../state/feed_provider.dart';
import '../../state/tabs_provider.dart';
import '../../utils/error_snackbar.dart';
import '../../utils/user_facing_error.dart';
import '../shell/transcribe_file_action.dart';

const _uuid = Uuid();

/// Haal de enclosure van [episode] op en open de transcriptie-
/// voorbeschouwing — handmatig, dus de volle medialimiet
/// ([maxFileSourceBytes]) en niet het autoDownload-plafond. Een eerder
/// automatisch gedownload stagingbestand wordt hergebruikt als het er
/// nog staat; de sessie-markering blijft zo zichtbaar.
Future<void> transcribeFeedEpisode(
  BuildContext context,
  WidgetRef ref, {
  required Uri feedUrl,
  required String feedTitle,
  required FeedEpisodeRecord episode,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final notifier = ref.read(feedStoreProvider.notifier);
  final name = episode.title.isEmpty
      ? p.basename(episode.enclosureUrl.path)
      : episode.title;

  if (isWebPlatform) {
    final result = await fetchFeed(
      episode.enclosureUrl,
      maxBytes: maxFileSourceBytes,
    );
    final bytes = result.bytes;
    if (!context.mounted) return;
    if (bytes == null) {
      showErrorSnackBar(
        messenger,
        l10n,
        _feedFailureMessage(l10n, result.failure),
      );
      return;
    }
    await openMediaBytesForTranscription(
      context,
      bytes,
      _mediaFileName(episode, name),
    );
    await notifier.markEpisode(feedUrl, episode.key, FeedEpisodeStatus.handled);
    return;
  }

  // Desktop: stagingbestand met een bruikbare extensie (de sniffer doet
  // de echte uitspraak, maar de decoder mag de hint gebruiken). Het pad
  // blijft staan — [downloadedPath] wijst erop en een volgende druk
  // hergebruikt het; het systeem ruimt zijn temp-map zelf op.
  final existing = episode.downloadedPath;
  String path;
  if (existing != null && await File(existing).exists()) {
    path = existing;
  } else {
    final dir = await getTemporaryDirectory();
    path = p.join(
      dir.path,
      'ocideck-feed-${_uuid.v4()}${_mediaExtension(episode)}',
    );
    final outcome = await downloadFeedMedia(
      episode.enclosureUrl,
      path,
      maxBytes: maxFileSourceBytes,
    );
    if (!context.mounted) return;
    if (outcome.path == null) {
      showErrorSnackBar(
        messenger,
        l10n,
        _feedFailureMessage(l10n, outcome.failure),
      );
      return;
    }
    await notifier.noteDownloadedPath(feedUrl, episode.key, path);
  }
  if (!context.mounted) return;
  await openMediaForTranscription(context, sourcePath: path, displayName: name);
  await notifier.markEpisode(feedUrl, episode.key, FeedEpisodeStatus.handled);
}

/// Haal een `podcast:transcript` op en open het als document — vóór
/// eigen ASR, zoals de feed bedoelde. Een onbruikbare lege omzetting is
/// een eerlijke melding, geen leeg document.
Future<void> fetchEpisodeTranscript(
  BuildContext context,
  WidgetRef ref, {
  required Uri feedUrl,
  required String feedTitle,
  required FeedEpisodeRecord episode,
  required FeedTranscriptLink link,
  FeedFetcher fetcher = fetchFeed,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final result = await fetcher(link.url);
  final bytes = result.bytes;
  if (!context.mounted) return;
  if (bytes == null) {
    showErrorSnackBar(
      messenger,
      l10n,
      _feedFailureMessage(l10n, result.failure),
    );
    return;
  }
  final markdown = episodeTranscriptMarkdown(
    text: utf8.decode(bytes, allowMalformed: true),
    link: link,
    feedTitle: feedTitle,
    episodeTitle: episode.title,
    fetchedAtLabel: DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
  );
  if (markdown == null) {
    showErrorSnackBar(
      messenger,
      l10n,
      l10n.d('Dit transcript is leeg of onleesbaar.'),
    );
    return;
  }
  ref
      .read(tabsProvider.notifier)
      .newDocumentFromMarkdown(
        markdown,
        suggestedName: episode.title.isEmpty ? feedTitle : episode.title,
      );
  await ref
      .read(feedStoreProvider.notifier)
      .markEpisode(feedUrl, episode.key, FeedEpisodeStatus.handled);
}

/// Dezelfde gerichte redenen als de URL-import — `importFailureMessage`
/// kent ze al.
String _feedFailureMessage(AppLocalizations l10n, ImportFailure? failure) =>
    importFailureMessage(l10n, failure ?? ImportFailure.network);

/// Bestandsnaam voor de `mem:`-sleutel / voorbeschouwing: de
/// afleveringstitel plus de containerextensie van de enclosure.
String _mediaFileName(FeedEpisodeRecord episode, String displayName) {
  final ext = _mediaExtension(episode);
  final base = displayName.endsWith(ext) ? displayName : '$displayName$ext';
  return base;
}

/// De extensie die bij de enclosure hoort: zijn URL-extensie als die er
/// is, anders een gok op het MIME-type. Alles onleesbaar → `.bin`; de
/// inhoudssniffer is de uitspraak, de extensie alleen een hint.
String _mediaExtension(FeedEpisodeRecord episode) {
  final fromUrl = p.extension(episode.enclosureUrl.path);
  if (fromUrl.length > 1 && fromUrl.length <= 5) return fromUrl;
  return switch (episode.enclosureType) {
    'audio/mpeg' => '.mp3',
    'audio/mp4' || 'video/mp4' => '.mp4',
    'audio/ogg' => '.ogg',
    'audio/wav' || 'audio/x-wav' => '.wav',
    'audio/flac' => '.flac',
    'video/webm' => '.webm',
    _ => '.bin',
  };
}
