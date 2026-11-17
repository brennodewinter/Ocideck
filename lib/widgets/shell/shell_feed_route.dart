// Part of the app_shell library — see ../app_shell.dart.
// De inhoudsrouter achter Openen via URL (#2931): de opgehaalde bytes
// classificeren vóór de deck-parsing. Een podcastfeed krijgt zijn eigen
// venster, een HTML-pagina met `link rel=alternate`-feeds een keuze —
// en al het andere loopt de bestaande deck-/importroutes.
part of '../app_shell.dart';

/// Wordt vanuit zowel de desktop- als de webroute aangeroepen met de
/// opgehaalde bytes. `true` = afgehandeld (dialoog getoond of keuze
/// gevolgd); `false` = geen feed aangetoond, de gewone import gaat door.
/// [depth] begrenst de ontdekkingsketen: een feedlink die wéér op een
/// pagina met feedlinks uitkomt valt terug op de gewone importfout —
/// eerlijker dan een tweede keuzevenster. Publiek voor de widget-tests
/// van de feedroute.
Future<bool> routeFeedUrlContent(
  BuildContext context,
  WidgetRef ref,
  String url,
  Uint8List bytes, {
  int depth = 0,
}) async {
  final verdict = classifyUrlContent(bytes, Uri.parse(url));
  switch (verdict.route) {
    case UrlContentRoute.feed:
      if (!context.mounted) return true;
      await showPodcastFeedDialog(context, verdict.feed!, Uri.parse(url));
      return true;
    case UrlContentRoute.feedCandidates:
      if (!context.mounted) return true;
      if (depth >= 1) return false;
      final chosen = await showFeedLinkChoiceDialog(context, verdict.feedLinks);
      // Afwijzen is ook afgehandeld: de gebruiker koos bewust geen feed.
      if (chosen == null) return true;
      if (!context.mounted) return true;
      await openDiscoveredFeedUrl(context, ref, chosen, depth: depth + 1);
      return true;
    case UrlContentRoute.notFeed:
      return false;
  }
}

/// Open een via `link rel=alternate` gevonden feed-URL via dezelfde
/// ophaalroute als de getikte URL — inclusief de router, zodat ook een
/// ontdekte link geen tweede keuzevenster kan forceren.
/// Nieuwe podcastafleveringen in de wachtrij (#2931): één melding per
/// toename — het beheer staat in de Podcastfeeds-dialoog achter
/// Importeren. Deze listener is tevens de opstekker van
/// feedStoreProvider: hij abonneert bij de eerste build, waarmee laden
/// en de periodieke controle vanaf app-start lopen. Publiek voor de
/// widget-tests.
void registerFeedListeners(WidgetRef ref, BuildContext context) {
  ref.listen<int>(feedFreshCountProvider, (prev, next) {
    if (next <= (prev ?? 0)) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.d(
            'Nieuwe podcastafleveringen — zie Importeren → Podcastfeeds.',
          ),
        ),
      ),
    );
  });
}

/// Publiek voor de widget-tests; productie bereikt hem via de keuze in
/// [routeFeedUrlContent].
Future<void> openDiscoveredFeedUrl(
  BuildContext context,
  WidgetRef ref,
  Uri url, {
  required int depth,
}) async {
  if (isWebPlatform) {
    await _importUrlWeb(
      context,
      ref,
      url.toString(),
      contentRouter: (bytes) => routeFeedUrlContent(
        context,
        ref,
        url.toString(),
        bytes,
        depth: depth,
      ),
    );
    return;
  }
  final failure = await ref
      .read(tabsProvider.notifier)
      .importFromUrl(
        url.toString(),
        homeDir: ref.read(settingsProvider).homeDirectory,
        contentRouter: (bytes) => routeFeedUrlContent(
          context,
          ref,
          url.toString(),
          bytes,
          depth: depth,
        ),
      );
  if (failure != null && context.mounted) {
    showErrorSnackBar(
      ScaffoldMessenger.of(context),
      context.l10n,
      importFailureMessage(context.l10n, failure),
    );
  }
}
