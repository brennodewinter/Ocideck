/// Lightweight logging for failures the app deliberately swallows.
///
/// Many call sites here used to be bare `catch (_) {}` blocks. Swallowing was
/// usually the *right* behaviour — a broken sidecar, an unreadable file or an
/// unsupported platform must never crash a presentation — but the failure then
/// vanished without a trace, which made real bugs invisible. Routing these
/// through [logError]/[logWarning] keeps the fail-soft behaviour while making
/// the cause observable.
///
/// Records go to the `dart:developer` logging stream (DevTools / the VM
/// service), not stdout, so release builds stay quiet. Pass only an operation
/// description and the caught error object — never deck or file *contents*,
/// which can be personal data.
///
/// Daarnaast gaat elke regel naar een [LogSink] als die is geïnstalleerd: in een
/// desktopbuild het lokale logbestand (`services/diagnostics/log_file.dart`).
/// Zonder dat bestand liet een release-build niets achter — de VM-service
/// bestaat daar niet — en waren "start niet" en "loopt vast" niet te
/// onderzoeken (#2618). Wat de schijf haalt, gaat eerst door [redactPaths].
library;

import 'dart:developer' as developer;

import 'content_hash.dart';

const _name = 'ocideck';

// Severity levels mirror package:logging (INFO = 800, WARNING = 900, SEVERE = 1000).
const int _levelInfo = 800;
const int _levelWarning = 900;
const int _levelError = 1000;

/// De foutwaarde zoals hij de logstroom in mag.
///
/// `FormatException.toString()` plakt een stuk van de ontlede brón in de
/// melding, en `jsonDecode` zet die bron op precies de tekst die werd ontleed.
/// Een mislukte decode van een dia-veld schreef daarmee de inhoud van die dia
/// weg — inclusief wat er aan bijzondere persoonsgegevens in stond. Het
/// doc-commentaar hierboven verbood dat al ("nooit deck- of bestandsinhoud"),
/// maar de aanroepers hielden zich eraan: het lek zat in het foutobject zelf.
///
/// De boodschap en de positie blijven; die heb je nodig om de fout te vinden.
/// De tekst eromheen niet.
Object _safeError(Object error) {
  if (error is FormatException) {
    final at = error.offset == null ? '' : ' (positie ${error.offset})';
    return 'FormatException: ${error.message}$at';
  }
  return error;
}

/// Publieke wrapper om [_safeError] voor aanroepers buiten dit bestand —
/// bijvoorbeeld `_transportSafe` in `import_task.dart`, dat de foutmelding
/// saniteert vóór de `cause` de isolate-grens passeert en in de UI landt.
Object sanitizeError(Object error) => _safeError(error);

/// An unexpected failure that was handled by falling back. [op] is a short
/// description of what was attempted, e.g. `'openDeck: read annotation sidecar'`.
void logError(String op, Object error, [StackTrace? stack]) {
  final safe = _safeError(error);
  developer.log(
    op,
    name: _name,
    error: safe,
    stackTrace: stack,
    level: _levelError,
  );
  _toSink('ERROR', op, safe, stack);
}

/// An expected-but-notable condition where the app fell back to a default
/// (e.g. an absent optional file, an unsupported platform capability). Lower
/// severity than [logError]; [error] is optional.
void logWarning(String op, [Object? error]) {
  final safe = error == null ? null : _safeError(error);
  developer.log(op, name: _name, error: safe, level: _levelWarning);
  _toSink('WARN', op, safe, null);
}

/// Een gebeurtenis die geen fout is maar die je achteraf wilt kunnen terugzien,
/// zoals een opstartmijlpaal of de versie waarmee een sessie begon.
void logInfo(String op) {
  developer.log(op, name: _name, level: _levelInfo);
  _toSink('INFO', op, null, null);
}

/// Een tweede bestemming naast de VM-service.
///
/// De vorm staat hier en de uitvoering elders, omdat dit bestand ook in de
/// webbuild zit en dus geen `dart:io` kan kennen.
abstract interface class LogSink {
  /// Eén complete regel, inclusief de afsluitende `\n`. Gooit nooit.
  void write(String line);

  /// Schrijf weg wat nog wacht en markeer de sessie als netjes beëindigd.
  Future<void> close();
}

LogSink? _sink;

/// Zet de bestemming naast de VM-service; `null` haalt hem weg.
void installLogSink(LogSink? sink) {
  _sink = sink;
  _repeats.clear();
}

/// Rond het logbestand af vlak voordat de app sluit. Mag vaker worden
/// aangeroepen; gooit nooit, want afsluiten mag hier niet op stuklopen.
Future<void> closeLog() async {
  try {
    await _sink?.close();
  } catch (e) {
    developer.log('closeLog', name: _name, error: e, level: _levelWarning);
  }
}

/// Zoveel keer mag dezelfde melding vrij door; daarna één op de
/// [_repeatSample], met de telling erbij. Een waarschuwing die bij elke build
/// afgaat, zou het begrensde bestand anders in een paar minuten vullen en
/// precies de opstartregels eruit duwen die je nodig had.
const _freeRepeats = 20;
const _repeatSample = 100;

/// Bovengrens op het aantal bijgehouden meldingen. Meldingen met een pad of
/// nummer erin zijn elk uniek; daarna begint de telling gewoon opnieuw.
const _maxTrackedOps = 2000;
final _repeats = <String, int>{};

/// Een foutobject kan lang zijn (een serverantwoord, een platformdetail); een
/// logregel hoeft dat niet.
const _maxErrorChars = 1000;

/// De bovenste frames zijn waar het om gaat; de rest is de event loop.
const _stackFrames = 12;

void _toSink(String level, String op, Object? error, StackTrace? stack) {
  final sink = _sink;
  if (sink == null) return;
  try {
    final head = redactPaths(op);
    final seen = _repeats.update(head, (n) => n + 1, ifAbsent: () => 1);
    if (_repeats.length > _maxTrackedOps) _repeats.clear();
    if (seen > _freeRepeats && seen % _repeatSample != 0) return;
    final line = StringBuffer()
      ..write(DateTime.now().toIso8601String())
      ..write(' $level $head');
    if (seen > _freeRepeats) line.write(' ($seen×)');
    if (error != null) {
      var text = '$error';
      if (text.length > _maxErrorChars) {
        text = '${text.substring(0, _maxErrorChars)}…';
      }
      line.write(' | ${redactPaths(text)}');
    }
    if (stack != null) {
      for (final frame in '$stack'.split('\n').take(_stackFrames)) {
        if (frame.trim().isNotEmpty) line.write('\n    ${redactPaths(frame)}');
      }
    }
    line.write('\n');
    sink.write(line.toString());
  } catch (e) {
    developer.log('logbestand', name: _name, error: e, level: _levelWarning);
  }
}

/// Een absoluut pad: een stationsletter, een UNC-share, `~/`, een `file:`-URI,
/// of een POSIX-pad van minstens twee delen. Het pad loopt door tot een
/// aanhalingsteken, een regeleinde, `]` of een `)` die het pad afsluit — spaties
/// horen erbij, want bestandsnamen hebben ze. Daardoor verdwijnt soms ook de
/// tekst na een pad midden in een melding; dat is de veilige kant om naar te
/// vallen.
///
/// Een URL blijft staan: `https://host/pad` begint niet met een losse `/`.
final _absolutePath = RegExp(
  r'''(?:file:/{1,3}(?:[A-Za-z]:)?|(?<!\w)[A-Za-z]:[\\/]|\\\\(?=[^\\\s])|(?<![\w.:/\\~-])~[\\/]|(?<![\w.:/\\~-])/(?=[^\s/]+/))'''
  r'''(?:[^'"\n\r)\]]|\)(?=[\\/]))*''',
);

final _shortExtension = RegExp(r'\.[A-Za-z0-9]{1,5}$');

/// Vervangt elk absoluut pad in [text] door `<pad#xxxxxxxx.ext>`: een korte
/// hash, zodat je ziet dat twee regels over hetzelfde bestand gaan, en de
/// extensie, zodat je ziet wát voor bestand. Een pad kan een gebruikersnaam en
/// een bestandsnaam dragen ("Ontslagbrief Jan.docx"), en het logbestand is iets
/// wat een gebruiker met ons deelt.
String redactPaths(String text) => text.replaceAllMapped(_absolutePath, (m) {
  final match = m[0]!;
  final path = match.trimRight();
  return '${_hashed('pad', path)}${match.substring(path.length)}';
});

/// Een bestandsnaam of relatief pad in een melding, zonder dat de naam zelf
/// in het log belandt: `<naam#xxxxxxxx.ext>`. Voor wat [redactPaths] niet kan
/// herkennen — een naam zonder map ervoor is voor een patroon gewoon een woord.
/// `log_no_content_test.dart` houdt bij welke variabelen hierdoor moeten.
String logName(String name) => _hashed('naam', name);

String _hashed(String kind, String value) {
  final last = value.split(RegExp(r'[\\/]')).last;
  final ext = _shortExtension.stringMatch(last) ?? '';
  return '<$kind#${sha256HexOfText(value).substring(0, 8)}$ext>';
}

/// Milliseconden sinds dit bestand voor het eerst werd geraakt; `main` doet
/// dat als eerste, dus in de praktijk: sinds de start.
final Stopwatch _clock = Stopwatch()..start();

/// De klok waarop opstartmijlpalen en werklabels hun tijd zetten.
int get logClockMs => _clock.elapsedMilliseconds;

/// Een opstartmijlpaal met de tijd sinds de start. Staat de laatste mijlpaal in
/// het logbestand, dan weet je waar een start bleef hangen.
void logMilestone(String what) => logInfo('opstart: $what (+$logClockMs ms)');

const _workSlots = 16;
final _workAt = List<int>.filled(_workSlots, -1);
final _workLabel = List<String>.filled(_workSlots, '');
var _workNext = 0;

/// Markeert het begin van zwaar, synchroon werk op de UI-isolate —
/// gezichtsscan, export, openen, documentsync.
///
/// Kost een paar nanoseconden en mag daarom op een pad dat per toetsaanslag
/// draait. De stallmelder (`services/diagnostics/ui_stall_watch.dart`) noemt
/// na een vastloper de labels die tijdens de vastloper zijn gezet: zo zegt de
/// logregel niet alleen hóé lang, maar ook wáárdoor. Een label hoort bij een
/// handeling, niet bij elk item erin; de ring onthoudt er [_workSlots].
void noteWork(String label) {
  _workAt[_workNext] = logClockMs;
  _workLabel[_workNext] = label;
  _workNext = (_workNext + 1) % _workSlots;
}

/// De werklabels die op of na [sinceMs] ([logClockMs]) zijn gezet, oudste
/// eerst en elk één keer.
List<String> workSince(int sinceMs) {
  final out = <String>[];
  for (var i = 0; i < _workSlots; i++) {
    final slot = (_workNext + i) % _workSlots;
    final label = _workLabel[slot];
    if (_workAt[slot] >= sinceMs && !out.contains(label)) out.add(label);
  }
  return out;
}
