// Het versieerbare livecontract voor de ASR-serverroute
// (docs/design/TRANSCRIPTION.md §4.3, #2525): protocol-id `vosk-ws-1` —
// het WebSocket-protocol van de zelf-hostbare vosk-server
// (alphacep/vosk-server, BSD-achtig), gekozen omdat het het enige
// gedocumenteerde, open streaming-ASR-protocol is dat een eigen server
// al spreekt. Een whisper-server (`POST /inference`) is bewust géén
// bewijs voor deze route: een batch-eindpunt kán geen voorlopige
// hypotheses leveren (de acceptatie van #2525 noemt dat expliciet).
//
// De draad, kort:
//  * client → server: één tekstframe `{"config":{…}}` bij het openen,
//    dan binaire frames met PCM s16le mono op de afgesproken samplerate,
//    dan één tekstframe `{"eof" : 1}` als de audio op is. Volgorde op de
//    draad ís de tijdsvolgorde — het protocol kent geen per-chunk
//    timestamp; de chunk-offsets van de capture zijn clientzijdig.
//  * server → client: `{"partial":"…"}`-hypotheses (mogen zichzelf
//    overschrijven) en `{"result":[…woordtijden…],"text":"…"}`-
//    uitspraken (definitief voor díe zin, nooit voor de opname — de
//    definitieve pass is en blijft `transcribe`).
//  * einde: `{"eof" : 1}` (byte-exact — zie [liveEofFrame]) en de server
//    sluit zijn resultaat af en de
//    socket; afbreken is de socket sluiten — er gaan geen audiopakketten
//    meer heen.
//  * hervatten bestaat niet in dit protocol: een nieuwe verbinding is
//    een nieuwe sessie en dus een nieuwe, zichtbare gebruikerskeuze.
//    Stil reconnecten is precies wat de sessieconsent verbiedt.
//  * backpressure: de draad kent geen credit-systeem; OciDeck begrenst
//    zijn eigen zendbuffer en meldt achterlopen via `LivePass`. De API-
//    sleutel gaat op io in de `Authorization`-header; een browser-WS kan
//    geen headers zetten, dus een sleutel-eisende live-server is op web
//    onbereikbaar — nooit in de URL of query (die staan in logs en
//    proxies).
import 'dart:convert';
import 'dart:typed_data';

/// De protocolversie die OciDeck aanbiedt. Wijzigt de draad, dan wijzigt
/// dit id — `AsrLiveServerEngine` claimt alleen dit.
const liveProtocolId = 'vosk-ws-1';

/// Het enige config-frame dat OciDeck stuurt. `words` vraagt
/// woordtijden zodat `result`-berichten een echte offset opleveren.
String buildLiveConfigFrame({required int sampleRate}) => jsonEncode({
  'config': {'sample_rate': sampleRate, 'words': true},
});

/// De afsluiter na het laatste audioblock. Geen audio — het
/// protocol-eindmerk, precies wat "stop zonder verdere audiopakketten"
/// op de draad betekent.
///
/// De spaties zijn geen stijl maar draadcontract: de referentieserver
/// (`websocket/asr_server.py`) vergelijkt de frame LETTERLIJK met
/// `'{"eof" : 1}'` — geen JSON-vergelijking. `{"eof" : 1}` wordt als audio
/// gelezen, gooit serverzijdig, en de socket sterft zonder slotresultaat
/// (bewezen tegen de echte Vosk in testbed/vosk-asr).
const liveEofFrame = '{"eof" : 1}';

/// Wat een tekstframe van de server kan zijn. Onbekende vormen zijn
/// invoer van een externe dienst: tellen mee als `LiveUnknown`, nooit
/// als crash.
sealed class LiveServerMessage {
  const LiveServerMessage._();
}

/// Een hypothese — mag elke volgende overschrijven. De UI markeert dit
/// sowieso al als voorlopig.
final class LivePartial extends LiveServerMessage {
  const LivePartial(this.text) : super._();
  final String text;
}

/// Eén woord met zijn tijden, zoals `result` ze levert (seconden).
final class LiveWord {
  const LiveWord({required this.word, required this.start, required this.end});

  final String word;
  final Duration start;
  final Duration end;
}

/// Een afgeronde uitspraak. `text` is de zin, `words` draagt de echte
/// offsets; leeg als de server ze niet stuurde.
final class LiveResult extends LiveServerMessage {
  const LiveResult({required this.text, this.words = const []}) : super._();

  final String text;
  final List<LiveWord> words;
}

/// Een frame dat geen van beide vormen heeft — genegeerd, geen fout.
final class LiveUnknown extends LiveServerMessage {
  const LiveUnknown() : super._();
}

/// Parseert één tekstframe. Defensief: elke kapotte of vreemde vorm
/// wordt [LiveUnknown] — de server is externe invoer, geen contract
/// dat we mogen aannemen.
LiveServerMessage parseLiveMessage(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on Object {
    return const LiveUnknown();
  }
  if (decoded is! Map) return const LiveUnknown();

  final partial = decoded['partial'];
  if (partial is String) return LivePartial(partial);

  final result = decoded['result'];
  final text = decoded['text'];
  if (result is List || text is String) {
    return LiveResult(
      text: text is String ? text : '',
      words: result is List ? _parseWords(result) : const [],
    );
  }
  return const LiveUnknown();
}

List<LiveWord> _parseWords(List<dynamic> result) {
  final words = <LiveWord>[];
  for (final raw in result) {
    if (raw is! Map) continue;
    final word = raw['word'];
    final start = raw['start'];
    final end = raw['end'];
    if (word is! String || start is! num || end is! num) continue;
    words.add(
      LiveWord(
        word: word,
        start: Duration(milliseconds: (start * 1000).round()),
        end: Duration(milliseconds: (end * 1000).round()),
      ),
    );
  }
  return words;
}

/// Haalt de PCM-payload uit een RIFF/WAVE-buffer: de eerste `data`-
/// chunk, teruggegeven als view op [bytes]. Null als er geen WAVE-kop of
/// geen data-chunk is — de aanroeper meldt dat als `DecodeFailed`,
/// niet als "geen spraak". Andere chunks (fmt, LIST, fact) worden op
/// hun lengteveld overgeslagen, even-afgerond zoals RIFF voorschrijft.
Uint8List? wavPcmData(Uint8List bytes) {
  if (bytes.length < 12) return null;
  bool eq(int off, List<int> tag) {
    for (var i = 0; i < tag.length; i++) {
      if (bytes[off + i] != tag[i]) return false;
    }
    return true;
  }

  const riff = [0x52, 0x49, 0x46, 0x46]; // 'RIFF'
  const wave = [0x57, 0x41, 0x56, 0x45]; // 'WAVE'
  const data = [0x64, 0x61, 0x74, 0x61]; // 'data'
  if (!eq(0, riff) || !eq(8, wave)) return null;

  int u32(int off) =>
      bytes[off] |
      (bytes[off + 1] << 8) |
      (bytes[off + 2] << 16) |
      (bytes[off + 3] << 24);

  var off = 12;
  while (off + 8 <= bytes.length) {
    final size = u32(off + 4);
    if (eq(off, data)) {
      final start = off + 8;
      final end = (start + size).clamp(start, bytes.length);
      return Uint8List.sublistView(bytes, start, end);
    }
    final next = off + 8 + size + (size & 1);
    if (next <= off) return null; // corrupte lengte — niet doorpogen
    off = next;
  }
  return null;
}
