// Het abonnementenoverzicht (#2931): gevolgde feeds met hun wachtrij,
// verversen/pauzeren/stoppen en de automatische downloadkeuze. Toont
// bewust ook wanneer de laatste controle faalde — een stille wachtrij
// die nooit bijwerkt is geen eerlijke wachtrij.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../services/feeds/feed_store.dart';
import '../../services/file_service.dart' show ImportFailure;
import '../../state/feed_provider.dart';
import '../../state/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/user_facing_error.dart';
import 'feed_dialog.dart';

/// De menupunt-ingang: het abonnementen- en wachtrijvenster.
Future<void> showFeedSubscriptionsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _FeedSubscriptionsDialog(),
  );
}

class _FeedSubscriptionsDialog extends ConsumerWidget {
  const _FeedSubscriptionsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final subs = ref.watch(feedStoreProvider);
    final aiEnabled = ref.watch(
      settingsProvider.select((s) => s.aiSettings.enabled),
    );
    return AlertDialog(
      title: Text(l10n.d('Podcastfeeds')),
      content: SizedBox(
        width: 560,
        child: subs.isEmpty
            ? Text(
                l10n.d(
                  'Nog geen gevolgde feeds. Open een podcastfeed via Openen via URL om hem te volgen.',
                ),
                style: TextStyle(fontSize: 13, color: AppTheme.slate600),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!aiEnabled)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        l10n.d(
                          'AI staat uit; controles en verwerking zijn gepauzeerd tot AI weer aanstaat.',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.slate600,
                        ),
                      ),
                    ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final sub in subs)
                          _subscriptionTile(context, ref, sub),
                      ],
                    ),
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

  Widget _subscriptionTile(
    BuildContext context,
    WidgetRef ref,
    FeedSubscription sub,
  ) {
    final l10n = context.l10n;
    final fresh =
        sub.episodes.values
            .where((e) => e.status == FeedEpisodeStatus.fresh)
            .toList()
          ..sort(
            (a, b) => (b.published ?? DateTime(0)).compareTo(
              a.published ?? DateTime(0),
            ),
          );
    final lastChecked = sub.lastChecked;
    final statusLine = <String>[
      if (lastChecked != null)
        '${l10n.d('Laatste controle')}: '
            '${DateFormat('yyyy-MM-dd HH:mm').format(lastChecked)}',
      if (sub.consecutiveFailures > 0)
        '${l10n.d('controles mislukt')}: ${sub.consecutiveFailures}',
      if (sub.paused) l10n.d('gepauzeerd'),
    ].join(' · ');
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: Text(
        sub.title.isEmpty ? sub.resolvedUrl.host : sub.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        [
          '${l10n.d('nieuw')}: ${fresh.length}',
          statusLine,
        ].where((s) => s.isNotEmpty).join(' · '),
        style: TextStyle(fontSize: 11, color: AppTheme.slate500),
      ),
      children: [
        // Wrap i.p.v. Row: drie actieknoppen mogen op een smal venster
        // (of 200% tekst) doorbreken naar een tweede regel.
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => _refresh(context, ref, sub),
              child: Text(l10n.d('Nu vernieuwen')),
            ),
            TextButton(
              onPressed: () => ref
                  .read(feedStoreProvider.notifier)
                  .setPaused(sub.feedUrl, !sub.paused),
              child: Text(
                sub.paused ? l10n.d('Hervatten') : l10n.d('Pauzeren'),
              ),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(feedStoreProvider.notifier).unfollow(sub.feedUrl),
              child: Text(l10n.d('Stoppen met volgen')),
            ),
          ],
        ),
        Row(
          children: [
            Switch(
              value: sub.autoDownload,
              onChanged: (v) => ref
                  .read(feedStoreProvider.notifier)
                  .setAutoDownload(sub.feedUrl, v),
            ),
            Expanded(
              child: Text(
                l10n.d('Nieuwe afleveringen automatisch downloaden'),
                style: TextStyle(fontSize: 12, color: AppTheme.slate600),
              ),
            ),
          ],
        ),
        if (fresh.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.d('Geen nieuwe afleveringen.'),
              style: TextStyle(fontSize: 12, color: AppTheme.slate500),
            ),
          )
        else
          for (final ep in fresh)
            feedQueueEpisodeTile(
              context,
              ref,
              ep,
              feedUrl: sub.feedUrl,
              feedTitle: sub.title,
            ),
      ],
    );
  }

  Future<void> _refresh(
    BuildContext context,
    WidgetRef ref,
    FeedSubscription sub,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      final count = await ref
          .read(feedStoreProvider.notifier)
          .refreshNow(sub.feedUrl);
      messenger.showSnackBar(
        SnackBar(content: Text('${l10n.d('nieuw')}: $count')),
      );
    } on ImportFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text(importFailureMessage(l10n, failure))),
      );
    }
  }
}
