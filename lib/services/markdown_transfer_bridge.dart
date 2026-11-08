import '../services/file_service.dart';
import 'markdown_transfer_protocol.dart';

/// Eén aangeboden Markdown-overdracht die op gebruikersinstemming wacht.
/// De schil toont hiervoor de toestemmingsvraag; [markdown] gaat pas de
/// openpoort in ná "Openen".
class InboundMarkdownRequest {
  const InboundMarkdownRequest({
    required this.id,
    required this.origin,
    required this.markdown,
    this.name,
  });
  final String id;
  final String origin;
  final String markdown;
  final String? name;
}

/// De state machine van de postMessage-browserkoppeling (#2827), bewust
/// zonder browser- of Flutter-afhankelijkheid zodat hij volledig in een
/// unittest loopt. De platformlaag ([startMarkdownListener]) levert
/// `data`, `origin` en `sourceIsParent` aan en voert [reply] uit met
/// `targetOrigin = origin` — nooit `'*'`.
///
/// Afspraken uit het protocol:
/// - berichten van een andere `source` dan de ouder-wordt-genegeerd;
/// - `init` van een toegestane origin krijgt `ready`, daarna mag die
///   precies één `open-markdown` insturen — de rest wordt genegeerd;
/// - een afgehandelde of ongeldige overdracht sluit de gereedmelding af;
///   de afzender moet opnieuw `init` sturen;
/// - antwoorden bevatten nooit documentinhoud.
class MarkdownTransferBridge {
  MarkdownTransferBridge({
    required this.trustedOrigins,
    required this.onRequest,
    this.maxMarkdownBytes = FileService.maxDeckMarkdownBytes,
  });

  /// Leeg = elke origin die de pagina mag insluiten mag vragen (de
  /// gebruiker beslist alsnog); gevuld = alleen deze origins mogen het
  /// initiatief nemen. `frame-ancestors` bepaalt wíé er überhaupt kan
  /// insluiten — dit is de tweede laag, geen vervanging ervoor.
  final List<String> trustedOrigins;
  final void Function(InboundMarkdownRequest) onRequest;
  final int maxMarkdownBytes;

  bool _ready = false;
  final _pending = <String, void Function(Map<String, Object?>)>{};

  bool get ready => _ready;
  int get pendingCount => _pending.length;

  /// Verwerk één message-event zoals de platformlaag het aanlevert.
  void handleMessage(
    Object? data,
    String origin,
    bool sourceIsParent,
    void Function(Map<String, Object?>) reply,
  ) {
    if (!sourceIsParent) return;
    if (data is! Map) return;
    final allowed = trustedOrigins.isEmpty || trustedOrigins.contains(origin);
    final parsed = parseTransferMessage(data);
    switch (parsed) {
      case TransferInit():
        // Zonder allowlist-entry eindigt het initiatief hier: `origin`
        // is de enige reden die we teruggeven, nooit inhoud.
        if (!allowed) return;
        _ready = true;
        reply(readyMessage());
      case TransferOpen():
        final id = parsed.id;
        if (!_ready) return;
        _ready = false;
        // Een afwijzing is óók een afgehandelde overdracht: altijd een
        // result terug als er een id is, en daarna weer `init` vereist.
        if (id == null || parsed.invalid != null) {
          if (id != null) {
            reply(resultMessage(id, kStatusRejected, reason: kReasonInvalid));
          }
          return;
        }
        if (!allowed) {
          reply(resultMessage(id, kStatusRejected, reason: kReasonOrigin));
          return;
        }
        final markdown = parsed.markdown!;
        if (!markdownFitsWithin(markdown, maxMarkdownBytes)) {
          reply(resultMessage(id, kStatusRejected, reason: kReasonTooLarge));
          return;
        }
        _pending[id] = reply;
        onRequest(
          InboundMarkdownRequest(
            id: id,
            origin: origin,
            markdown: markdown,
            name: parsed.name,
          ),
        );
      case TransferIgnore():
        return;
    }
  }

  /// Beantwoord een openstaande aanvraag; de schil roept dit na de
  /// toestemmingsvraag en de openpoort. Een tweede answer op hetzelfde
  /// id is een no-op — het antwoord is al verstuurd.
  void answer(String id, String status, {String? reason}) {
    _pending.remove(id)?.call(resultMessage(id, status, reason: reason));
  }
}
