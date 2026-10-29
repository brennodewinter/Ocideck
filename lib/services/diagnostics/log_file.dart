import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../utils/log.dart';

/// Het lokale logbestand van een desktopbuild (#2618).
///
/// Twee bestanden van elk hooguit [maxBytes]: `<naam>.log` en, na een
/// rotatie, `<naam>.1.log`. Meer wordt het nooit — het is een vluchtrecorder,
/// geen archief. Er komt alleen in wat `utils/log.dart` doorgeeft, en dat heeft
/// de paden er al uit gehaald.
///
/// **Waarom eerst synchroon.** Tot het eerste frame schrijft elke regel meteen
/// naar schijf, op de UI-isolate. Een start die vastloopt in synchroon werk
/// houdt de event loop vast, en dan komt een asynchrone schrijfactie nooit meer
/// aan de beurt — precies de regels die zeggen wáár hij vastliep, zouden dan
/// ontbreken. Vóór het eerste frame zijn het een handvol regels. Daarna
/// ([writeInBackground]) gaan ze gebundeld en asynchroon, zodat een waarschuwing
/// in een buildpad de UI niet laat wachten op de schijf.
///
/// **De sessiemarkering.** Met een `sessionInfo` legt [open] een `<naam>.sessie`
/// neer die [close] bij een nette afsluiting weer weghaalt. Ligt hij er bij de
/// volgende start nog, dan staat in [previousSession] wanneer die vorige sessie
/// begon: de app is toen vastgelopen, geforceerd beëindigd of met de computer
/// mee uitgezet.
class LogFile implements LogSink {
  LogFile._(
    this._current,
    this._previous,
    this._marker,
    this._size,
    this.maxBytes,
  );

  /// De grootte waarboven het bestand roteert.
  static const defaultMaxBytes = 1024 * 1024;

  /// Open (of maak) `<dir>/<name>.log`. Gooit bij een schijffout; de aanroeper
  /// draait dan zonder logbestand verder.
  static LogFile open(
    Directory dir, {
    String name = 'ocideck',
    String? sessionInfo,
    int maxBytes = defaultMaxBytes,
  }) {
    dir.createSync(recursive: true);
    final current = File(p.join(dir.path, '$name.log'));
    final log = LogFile._(
      current,
      File(p.join(dir.path, '$name.1.log')),
      sessionInfo == null ? null : File(p.join(dir.path, '$name.sessie')),
      current.existsSync() ? current.lengthSync() : 0,
      maxBytes,
    );
    final marker = log._marker;
    if (marker != null) {
      if (marker.existsSync()) {
        log.previousSession = marker.readAsStringSync().trim();
      }
      // ponytail: één markering per naam. Een tweede exemplaar van de app (geen
      // enkel-exemplaarbewaking op Windows, #2627) ziet die van het eerste als
      // "niet netjes afgesloten"; per-proces markeren hoort bij #2627.
      _appendBytesSync(marker, utf8.encode('$sessionInfo\n'), FileMode.write);
    }
    return log;
  }

  final File _current;
  final File _previous;
  final File? _marker;
  final int maxBytes;
  int _size;

  /// Wanneer de vorige sessie begon, als die niet netjes is afgesloten.
  String? previousSession;

  bool _immediate = true;
  bool _broken = false;
  bool _draining = false;
  Future<void> _drainFuture = Future.value();
  final _pending = StringBuffer();
  int _dropped = 0;

  /// De map met de logbestanden — voor "Logmap openen".
  Directory get directory => _current.parent;

  @override
  void write(String line) {
    if (_broken) return;
    if (_immediate) {
      try {
        _appendSync(line);
      } catch (e) {
        _fail(e);
      }
      return;
    }
    // Een vloed regels terwijl de schijf nog bezig is: niet onbegrensd
    // bufferen. Wat er niet in past, wordt geteld en als één regel gemeld.
    if (_pending.length > maxBytes ~/ 4) {
      _dropped++;
      return;
    }
    _pending.write(line);
    if (!_draining) {
      _draining = true;
      _drainFuture = _drainPending();
    }
  }

  /// Vanaf het eerste frame: bundelen en asynchroon schrijven.
  void writeInBackground() => _immediate = false;

  @override
  Future<void> close() async {
    await _settle();
    try {
      if (_pending.isNotEmpty) {
        _appendSync(_pending.toString());
        _pending.clear();
      }
      final marker = _marker;
      if (marker != null && marker.existsSync()) marker.deleteSync();
    } catch (e) {
      _fail(e);
    }
  }

  /// De laatste [count] regels over beide bestanden heen, oudste eerst.
  Future<List<String>> tail(int count) async {
    await _settle();
    final lines = <String>[];
    for (final file in [_previous, _current]) {
      if (!await file.exists()) continue;
      final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      lines.addAll(const LineSplitter().convert(text));
    }
    return lines.length <= count ? lines : lines.sublist(lines.length - count);
  }

  Future<void> _settle() async {
    while (_draining) {
      await _drainFuture;
    }
  }

  Future<void> _drainPending() async {
    try {
      while (_pending.isNotEmpty) {
        if (_dropped > 0) {
          _pending.write(
            '${DateTime.now().toIso8601String()} WARN logbestand: '
            '$_dropped regels overgeslagen\n',
          );
          _dropped = 0;
        }
        final chunk = utf8.encode(_pending.toString());
        _pending.clear();
        if (_size > 0 && _size + chunk.length > maxBytes) await _rotate();
        final raf = await _current.open(mode: FileMode.append);
        try {
          await raf.writeFrom(chunk);
        } finally {
          await raf.close();
        }
        _size += chunk.length;
      }
    } catch (e) {
      _fail(e);
    } finally {
      _draining = false;
    }
  }

  Future<void> _rotate() async {
    if (await _previous.exists()) await _previous.delete();
    await _current.rename(_previous.path);
    _size = 0;
  }

  void _appendSync(String text) {
    final bytes = utf8.encode(text);
    if (_size > 0 && _size + bytes.length > maxBytes) {
      if (_previous.existsSync()) _previous.deleteSync();
      _current.renameSync(_previous.path);
      _size = 0;
    }
    _appendBytesSync(_current, bytes, FileMode.append);
    _size += bytes.length;
  }

  static void _appendBytesSync(File file, List<int> bytes, FileMode mode) {
    final raf = file.openSync(mode: mode);
    try {
      raf.writeFromSync(bytes);
    } finally {
      raf.closeSync();
    }
  }

  /// Een logbestand dat niet wil, mag de app niet hinderen: uitzetten en de
  /// reden nog één keer naar de VM-service sturen ([_broken] houdt de sink
  /// daarbij buiten de deur).
  void _fail(Object error) {
    _broken = true;
    logWarning('LogFile: logbestand uitgeschakeld', error);
  }
}
