/// Het berichtformaat van de postMessage-browserkoppeling (#2827):
/// een externe website die OciDeck insluit (iframe) kan één Markdown-tekst
/// aanbieden om te openen.
///
/// Protocol (één overdracht per gereedmelding):
///
///   afzender → OciDeck  {"type":"ocideck:init","version":1}
///   OciDeck  → afzender  {"type":"ocideck:ready","version":1}
///   afzender → OciDeck  {"type":"ocideck:open-markdown","version":1,
///                        "id":"x","name":"x.md","markdown":"…"}
///   OciDeck  → afzender  {"type":"ocideck:result","version":1,"id":"x",
///                        "status":"opened"|"declined"|"rejected",
///                        "reason":"tooLarge"|"unsafe"|"invalid"|"origin"}
///
/// Berichten vóór `ready`, na een afgehandelde overdracht, of met een
/// onbekend `type` of `version` worden genegeerd — de afzender herhaalt
/// `init` tot `ready` terugkomt, wat ook het laadgat dekt: een te vroege
/// `init` raakt nooit tekst kwijt. Antwoorden bevatten nooit
/// documentinhoud. Gedocumenteerd in docs/HOSTING.md en
/// docs/SECURITY_DESIGN.md.
library;

import 'dart:convert';

const kTransferVersion = 1;
const kTypeInit = 'ocideck:init';
const kTypeOpenMarkdown = 'ocideck:open-markdown';
const kTypeReady = 'ocideck:ready';
const kTypeResult = 'ocideck:result';

const kStatusOpened = 'opened';
const kStatusDeclined = 'declined';
const kStatusRejected = 'rejected';

const kReasonTooLarge = 'tooLarge';
const kReasonUnsafe = 'unsafe';
const kReasonInvalid = 'invalid';
const kReasonOrigin = 'origin';

/// Wat er uit een binnenkomend bericht valt te maken. `ignore` dekt alles
/// dat geen geldige `init` of `open-markdown` is — inclusief een verkeerde
/// versie of niet-map-payload, want zwijgen is daar het antwoord.
sealed class InboundTransfer {
  const InboundTransfer();
}

final class TransferInit extends InboundTransfer {
  const TransferInit();
}

/// Een geldige `open-markdown` die inhoudelijk getoetst moet worden:
/// [invalid] is de afwijsreden wanneer verplichte velden ontbreken of van
/// het verkeerde type zijn; is die null, dan is de tekst bruikbaar.
final class TransferOpen extends InboundTransfer {
  const TransferOpen({
    required this.id,
    this.name,
    this.markdown,
    this.invalid,
  });
  final String? id;
  final String? name;
  final String? markdown;
  final String? invalid;
}

final class TransferIgnore extends InboundTransfer {
  const TransferIgnore();
}

/// Parse `event.data` van een message-event. Verwacht een Dart-map zoals
/// `dartify()` die oplevert; alles anders is stil te negeren.
InboundTransfer parseTransferMessage(Object? data) {
  if (data is! Map) return const TransferIgnore();
  if (data['type'] is! String) return const TransferIgnore();
  if (data['version'] != kTransferVersion) return const TransferIgnore();
  switch (data['type']) {
    case kTypeInit:
      return const TransferInit();
    case kTypeOpenMarkdown:
      final id = data['id'];
      final markdown = data['markdown'];
      final name = data['name'];
      final invalid = id is! String || id.isEmpty
          ? 'missing id'
          : markdown is! String
          ? 'missing markdown'
          : (name != null && name is! String)
          ? 'bad name'
          : null;
      return TransferOpen(
        id: id is String ? id : null,
        name: name is String ? name : null,
        markdown: markdown is String ? markdown : null,
        invalid: invalid,
      );
    default:
      return const TransferIgnore();
  }
}

/// Meet de UTF-8-omvang van [markdown] zonder altijd te coderen: een
/// tekst die in karakters al over [maxBytes] zit is sowieso te groot;
/// alleen eronder hoeft de echte codering te tonen.
bool markdownFitsWithin(String markdown, int maxBytes) {
  if (markdown.length > maxBytes) return false;
  return utf8.encode(markdown).length <= maxBytes;
}

Map<String, Object?> readyMessage() => {
  'type': kTypeReady,
  'version': kTransferVersion,
};

Map<String, Object?> resultMessage(
  String id,
  String status, {
  String? reason,
}) => {
  'type': kTypeResult,
  'version': kTransferVersion,
  'id': id,
  'status': status,
  'reason': ?reason,
};
