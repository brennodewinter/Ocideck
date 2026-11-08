import 'package:ocideck/services/markdown_transfer_bridge.dart';
import 'package:ocideck/services/markdown_transfer_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

/// De postMessage-browserkoppeling (#2827): de state machine die beslist
/// wat met een bericht gebeurt. De browserlaag eromheen is dun — één
/// addEventListener en één postMessage — dus bijna alles bewijsbare ligt
/// hier, in pure Dart.
void main() {
  final replies = <Map<String, Object?>>[];
  final requests = <InboundMarkdownRequest>[];

  late MarkdownTransferBridge bridge;

  void send(
    Object? data, {
    String origin = 'https://intake.example',
    bool sourceIsParent = true,
  }) {
    bridge.handleMessage(data, origin, sourceIsParent, (r) => replies.add(r));
  }

  Map<String, Object?> msg(Map<String, Object?> extra) => {
    'type': kTypeInit,
    'version': kTransferVersion,
    ...extra,
  };

  void init({String origin = 'https://intake.example'}) =>
      send(msg({}), origin: origin);

  void offer({
    String origin = 'https://intake.example',
    String markdown = '# hoi',
    String id = 'r1',
  }) => send(
    msg({
      'type': kTypeOpenMarkdown,
      'id': id,
      'name': 'a.md',
      'markdown': markdown,
    }),
    origin: origin,
  );

  setUp(() {
    replies.clear();
    requests.clear();
    bridge = MarkdownTransferBridge(
      trustedOrigins: const [],
      onRequest: requests.add,
      maxMarkdownBytes: 10,
    );
  });

  test('init → ready; open-markdown levert één aanvraag op', () {
    init();
    expect(replies.single['type'], kTypeReady);
    expect(bridge.ready, isTrue);
    offer();
    expect(requests.single.origin, 'https://intake.example');
    expect(requests.single.markdown, '# hoi');
    expect(bridge.pendingCount, 1);
  });

  test('open-markdown vóór ready wordt genegeerd', () {
    offer();
    expect(requests, isEmpty);
    expect(replies, isEmpty);
  });

  test('na een afgehandelde overdracht is opnieuw init vereist', () {
    init();
    offer();
    bridge.answer('r1', kStatusOpened);
    expect(replies.last['status'], kStatusOpened);
    offer(id: 'r2');
    expect(requests, hasLength(1));
  });

  test('berichten van een andere source dan de ouder tellen niet', () {
    send(msg({}), sourceIsParent: false);
    expect(replies, isEmpty);
    expect(bridge.ready, isFalse);
  });

  test('verkeerde versie of type wordt stil genegeerd', () {
    send({'type': kTypeInit, 'version': 99});
    send({'type': 'ocideck:hack', 'version': 1});
    expect(replies, isEmpty);
  });

  test('te groot bericht → rejected/tooLarge, zonder aanvraag', () {
    init();
    offer(markdown: 'dit is veel te lang');
    expect(requests, isEmpty);
    expect(replies.last['status'], kStatusRejected);
    expect(replies.last['reason'], kReasonTooLarge);
    // Multibyte telt in UTF-8-bytes, niet in karakters.
    init();
    replies.clear();
    offer(markdown: '€€€€'); // 4 tekens, 12 bytes > 10
    expect(replies.last['reason'], kReasonTooLarge);
  });

  test('ontbrekende velden → rejected/invalid', () {
    init();
    send(msg({'type': kTypeOpenMarkdown, 'id': 'r9'}));
    expect(replies.last['reason'], kReasonInvalid);
    expect(requests, isEmpty);
  });

  test('allowlist: verkeerde origin → rejected/origin of stilte bij init', () {
    bridge = MarkdownTransferBridge(
      trustedOrigins: const ['https://intake.example'],
      onRequest: requests.add,
      maxMarkdownBytes: 10,
    );
    init(origin: 'https://evil.example');
    expect(replies, isEmpty);
    init();
    offer();
    expect(requests, hasLength(1));
  });

  test('weigering en afwijzingen komen als result terug, zonder inhoud', () {
    init();
    offer();
    bridge.answer('r1', kStatusDeclined);
    expect(replies.last['status'], kStatusDeclined);
    expect(replies.last.containsKey('markdown'), isFalse);
    bridge.answer('r1', kStatusOpened); // dubbel antwoord is een no-op
    expect(replies.where((r) => r['type'] == kTypeResult), hasLength(1));
  });
}
