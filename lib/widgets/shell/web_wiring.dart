part of '../app_shell.dart';

/// Web-wiring rond de twee browser-ingangen: de `?deck=`-deeplink (#2826)
/// en de postMessage-browserkoppeling (#2827). Losse top-level functies in
/// dezelfde library — [_AppShellState] riep ze als methodes aan, maar ze
/// dragen geen eigen widget-state en droegen alleen bij aan de omvang van
/// die klasse. `isMounted` gaat mee als callback omdat een top-level
/// functie zelf geen `mounted` heeft.

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

/// De bridge bewaakt het protocol (init → ready → één overdracht);
/// alles wat bij de gebruiker moet komen gaat via
/// [inboundMarkdownRequestProvider].
Future<MarkdownTransferBridge> _startMarkdownTransferBridge(
  WidgetRef ref,
  bool Function() isMounted,
) async {
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
  return bridge;
}

/// Beantwoord een aangeboden overdracht: weigeren stuurt `declined`;
/// openen gaat door exact dezelfde poort als geplakte tekst (#2825) en
/// de site krijgt alleen de uitkomst — `unsafe`/`invalid`, nooit inhoud.
Future<void> _answerMarkdownTransfer(
  BuildContext context,
  WidgetRef ref,
  InboundMarkdownRequest request,
  MarkdownTransferBridge? bridge,
) async {
  if (bridge == null || !context.mounted) return;
  final consent = await MarkdownTransferConsentDialog.show(
    context,
    origin: request.origin,
    name: request.name,
  );
  if (!context.mounted) return;
  if (!consent) {
    bridge.answer(request.id, kStatusDeclined);
    return;
  }
  ref.read(openFailureProvider.notifier).state = null;
  final result = await ref
      .read(tabsProvider.notifier)
      .openDeckFromBytes(
        Uint8List.fromList(utf8.encode(request.markdown)),
        request.name ?? 'overdracht.md',
      );
  if (result == OpenResult.opened) {
    bridge.answer(request.id, kStatusOpened);
  } else if (result == OpenResult.blocked) {
    bridge.answer(request.id, kStatusRejected, reason: kReasonUnsafe);
  } else {
    bridge.answer(request.id, kStatusRejected, reason: kReasonInvalid);
  }
}

/// Start de postMessage-browserkoppeling (#2827): luistert naar een
/// insluitende site en stuurt elke aanbieding via
/// [inboundMarkdownRequestProvider] aan de toestemmingsvraag. Vóór
/// `ocideck:ready` gaat geen tekst de openpoort in.
void _initMarkdownTransfer(WidgetRef ref, bool Function() isMounted) {
  if (!isWebPlatform) return;
  unawaited(() async {
    final bridge = await _startMarkdownTransferBridge(ref, isMounted);
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
      _answerMarkdownTransfer(context, ref, request, _markdownTransferBridge),
    );
  });
}
