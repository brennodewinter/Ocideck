part of '../app_shell.dart';

/// Web-wiring rond de twee browser-ingangen: de `?deck=`-deeplink (#2826)
/// en de postMessage-browserkoppeling (#2827). Losse top-level functies in
/// dezelfde library — [_AppShellState] riep ze als methodes aan, maar ze
/// dragen geen eigen widget-state en droegen alleen bij aan de omvang van
/// die klasse. `isMounted` gaat mee als callback omdat een top-level
/// functie zelf geen `mounted` heeft.
///
/// Het stuk dat UI én de openpoort raakt ([answerMarkdownTransfer]) staat
/// apart als gewone library — een `part` is niet los te testen.

/// De postMessage-browserkoppeling (#2827): een insluitende site kan één
/// Markdown-tekst aanbieden. Top-level in deze library — er is maar één
/// AppShell, en de bridge bewaakt geen UI-state.
MarkdownTransferBridge? _markdownTransferBridge;

/// Web-deeplink: `?deck=<url>` haalt de presentatie op en opent haar —
/// één link deelt zo de app én de inhoud. De volledige importpoort
/// (CORS/hulppunt, veiligheidsscan met alarm, marp-controle) blijft gelden.
Future<void> _openDeckDeepLink(
  BuildContext context,
  WidgetRef ref,
  bool Function() isMounted,
) async {
  if (!isWebPlatform || !isMounted()) return;
  final deckUrl = deckDeepLinkFrom(Uri.base);
  if (deckUrl == null) return;
  final result = await _importUrlWeb(context, ref, deckUrl);
  // Besluit (#2826): bij een geopend deck wissen we `?deck=` uit de
  // adresbalk — anders haalt elke herlading het bestand opnieuw binnen
  // als extra tabblad. Bij een míslukte open blijft hij bewust staan:
  // dan is herladen om opnieuw te proberen juist het nuttige gedrag.
  if (result == OpenResult.opened) {
    replaceAddressBar(withoutDeckParam(Uri.base));
  }
}

/// Start de postMessage-browserkoppeling (#2827): luistert naar een
/// insluitende site en stuurt elke aanbieding via
/// [inboundMarkdownRequestProvider] aan de toestemmingsvraag. De bridge
/// bewaakt het protocol (init → ready → één overdracht); vóór
/// `ocideck:ready` gaat geen tekst de openpoort in.
void _initMarkdownTransfer(WidgetRef ref, bool Function() isMounted) {
  if (!isWebPlatform) return;
  unawaited(() async {
    final origins = await fetchTrustedMessageOrigins();
    final bridge = MarkdownTransferBridge(
      trustedOrigins: origins,
      onRequest: (request) {
        // De luisteraar overleeft de shell; zonder deze check schrijft een
        // laat binnenkomend bericht op een weggegooide ref.
        if (!isMounted()) return;
        ref.read(inboundMarkdownRequestProvider.notifier).state = request;
      },
    );
    startMarkdownListener(bridge.handleMessage);
    if (isMounted()) _markdownTransferBridge = bridge;
  }());
}

/// Een externe website biedt Markdown aan via postMessage (#2827): de
/// toestemmingsvraag met de origin, en pas na "Openen" dezelfde openpoort
/// als geplakte tekst. Het antwoord aan de site draagt nooit inhoud.
void _watchMarkdownTransferRequests(BuildContext context, WidgetRef ref) {
  ref.listen<InboundMarkdownRequest?>(inboundMarkdownRequestProvider, (
    _,
    request,
  ) {
    if (request == null) return;
    ref.read(inboundMarkdownRequestProvider.notifier).state = null;
    unawaited(
      answerMarkdownTransfer(context, ref, request, _markdownTransferBridge),
    );
  });
}
