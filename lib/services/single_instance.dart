import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../platform/launch_files.dart';
import '../utils/log.dart';

/// Eén exemplaar per gebruiker via een Unix-socket — de Linux-tegenhanger van
/// de Windows-mutex + WM_COPYDATA-doorgifte uit #2627 (#2656).
///
/// De eerste starter bindt de socket en wordt de primaire; elke volgende
/// starter verbindt, stuurt zijn te-openen paden door ('\n'-gescheiden UTF-8,
/// precies als WM_COPYDATA) en stopt vóór `runApp`. Een afgesloten socket zonder
/// luisteraar is het restant van een crash of harde kill — die gaat weg en de
/// starter bindt opnieuw.
///
/// Alles in Dart, bewust: dezelfde code toetst op macOS (unix-sockets werken
/// daar identiek) terwijl hij alleen op Linux aanstaat.
class SingleInstanceGuard {
  SingleInstanceGuard({
    String? socketPath,
    this.replyTimeout = const Duration(seconds: 2),
  }) : _socketPath = socketPath == null
           ? defaultSocketPath()
           : Future.value(socketPath);

  final Future<String?> _socketPath;
  static const _maxFrameBytes = 64 * 1024;
  static const _maxPaths = 128;
  static const _maxConnections = 16;
  static const _maxPendingPaths = 256;
  var _connections = 0;

  /// Hoe lang een tweede starter op `ok` van de primaire wacht. Langer dan
  /// dit is een hangende primaire, geen geslaagde overdracht (#2679).
  final Duration replyTimeout;

  ServerSocket? _server;
  void Function(List<String> paths)? _onFiles;
  void Function()? _onActivate;
  bool _activatePending = false;

  /// De verbinding kwam tot stand, maar de primaire stuurde geen `ok`.
  /// De aanroeper mag dan niet doen alsof de overdracht slaagde.
  bool primaryDidNotAnswer = false;

  /// Paden die aankwamen terwijl de UI-handler er nog niet was: de socket
  /// bindt vroeg in `main()`, de shell hangt haar opener pas ná de eerste
  /// frame. Zonder buffer zou een tweede starter in die kloof stil verliezen.
  final List<String> _pending = [];

  /// De UI-opener registreren (de shell, via [OpenFileChannel.start]). Wat er
  /// tussen bind en deze setter binnenkwam, wordt meteen afgeleverd.
  set onFiles(void Function(List<String> paths) handler) {
    _onFiles = handler;
    if (_pending.isEmpty) return;
    final drained = List<String>.from(_pending);
    _pending.clear();
    handler(drained);
  }

  /// Een tweede start zonder pad — menu, dock, `.desktop` — moet het
  /// bestaande venster naar voren halen. De handler komt pas met de shell;
  /// een bericht in die kloof blijft één keer liggen.
  set onActivate(void Function() handler) {
    _onActivate = handler;
    if (!_activatePending) return;
    _activatePending = false;
    handler();
  }

  void _requestActivate() {
    final handler = _onActivate;
    if (handler == null) {
      _activatePending = true;
      return;
    }
    handler();
  }

  /// De Linux-runtime-directory hoort volgens de XDG-specificatie privé te
  /// zijn. Zonder die gebruikersgrens opent OciDeck een eigen venster.
  static Future<String?> defaultSocketPath() async {
    final runtimeDir = Platform.environment['XDG_RUNTIME_DIR'];
    if (!Platform.isLinux || runtimeDir == null || !p.isAbsolute(runtimeDir)) {
      return null;
    }
    try {
      final real = await Directory(runtimeDir).resolveSymbolicLinks();
      if (await FileSystemEntity.type(real, followLinks: false) !=
          FileSystemEntityType.directory) {
        return null;
      }
      // /proc/self hoort bij het stat-proces zelf, dat met onze uid draait.
      // Het uitvoerformaat bestaat uit twee korte regels met uid en modus.
      final stat = await Process.start('/usr/bin/stat', [
        '-Lc',
        '%u:%a',
        '--',
        '/proc/self',
        real,
      ], includeParentEnvironment: false);
      try {
        final results = await Future.wait<Object>([
          stat.exitCode,
          utf8.decoder.bind(stat.stdout).join(),
          stat.stderr.drain<void>().then((_) => ''),
        ]).timeout(const Duration(seconds: 1));
        if (results[0] != 0) return null;
        final lines = (results[1] as String).trim().split('\n');
        final uid = lines.first.split(':').first;
        if (lines.length == 2 && lines[1] == '$uid:700') {
          return p.join(real, 'ocideck.sock');
        }
      } on TimeoutException {
        stat.kill(ProcessSignal.sigkill);
      }
    } catch (error) {
      logWarning('SingleInstanceGuard: privédirectory niet beschikbaar', error);
    }
    return null;
  }

  Future<Socket> _connect(String path) => Socket.connect(
    InternetAddress(path, type: InternetAddressType.unix),
    0,
    timeout: replyTimeout,
  );

  /// `true` alleen als de primaire `ok` terugstuurde. Een lege [paths] is
  /// een echte start zonder bestand: de primaire haalt dan alleen het
  /// venster naar voren. Geen antwoord binnen [replyTimeout] is een
  /// hangende primaire — dan `false`, zodat deze start niet stil verdwijnt.
  Future<bool> forwardToPrimary(List<String> paths) async {
    primaryDidNotAnswer = false;
    final path = await _socketPath;
    if (path == null) return false;
    final lines = paths.where(looksLikeDeckLaunchArg).toList();
    if (lines.length > _maxPaths ||
        lines.any((line) => line.contains('\n') || line.contains('\r'))) {
      return false;
    }
    final payload = utf8.encode(
      '${lines.length}\n${lines.map((line) => '$line\n').join()}',
    );
    if (payload.length > _maxFrameBytes) return false;
    final Socket socket;
    try {
      socket = await _connect(path);
    } catch (e) {
      // Connect geweigerd = het normale pad: geen primaire → deze starter
      // wordt zelf de primaire. Stil terugvallen is hier de bedoeling.
      return false;
    }
    try {
      socket.add(payload);
      await socket.flush().timeout(replyTimeout);
      final reply = await _decodeLimited(
        socket,
        16,
      ).join().timeout(replyTimeout);
      final ok = reply == 'ok\n';
      if (!ok) primaryDidNotAnswer = true;
      return ok;
    } on TimeoutException {
      primaryDidNotAnswer = true;
      return false;
    } catch (e) {
      primaryDidNotAnswer = true;
      logWarning('SingleInstanceGuard: paden doorsturen mislukt', e);
      return false;
    } finally {
      socket.destroy();
    }
  }

  /// Word de primaire: bind de socket en dien inkomende paden aan [onFiles]
  /// zodra die geregistreerd is. Eén verwijder-opnieuw-bind ronde vangt het
  /// achtergelaten bestand van een gecrashte vorige sessie af. Faalt ook de
  /// tweede bind, dan loopt de app onbewaakt door — de status quo vandaag,
  /// geen reden om een bruikbare start te weigeren.
  Future<void> becomePrimary() async {
    final path = await _socketPath;
    if (path == null || _server != null) return;
    _server = await _bind(path);
    if (_server == null) {
      try {
        // Een bereikbare listener kan traag zijn, maar bezit zijn socket.
        final running = await _connect(path);
        running.destroy();
        return;
      } on SocketException {
        // Alleen een achtergebleven pad in de privédirectory opruimen.
      } on TimeoutException {
        return;
      }
      try {
        await File(path).delete();
      } catch (e) {
        logWarning('SingleInstanceGuard: stale socket wissen mislukt', e);
      }
      _server = await _bind(path);
    }
    if (_server == null) {
      logWarning(
        'SingleInstanceGuard: geen socket gebonden — geen enkel-exemplaar-poort',
      );
      return;
    }
    _server!.listen((connection) async {
      if (_connections >= _maxConnections) {
        connection.destroy();
        return;
      }
      _connections++;
      try {
        final paths = await _readFramedPaths(connection).timeout(replyTimeout);
        if (_onFiles == null &&
            _pending.length + paths.length > _maxPendingPaths) {
          throw const FormatException('Too many pending launch paths');
        }
        // Elk bericht, ook een leeg, haalt het venster naar voren. Een
        // tweede start zonder bestand deed hiervoor niets zichtbaars.
        _requestActivate();
        if (paths.isNotEmpty) {
          final handler = _onFiles;
          if (handler == null) {
            _pending.addAll(paths);
          } else {
            handler(paths);
          }
        }
        connection.write('ok\n');
        await connection.flush().timeout(replyTimeout);
      } catch (e) {
        logWarning('SingleInstanceGuard: bericht van tweede starter', e);
      } finally {
        connection.destroy();
        _connections--;
      }
    });
  }

  Future<ServerSocket?> _bind(String path) async {
    try {
      return await ServerSocket.bind(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
    } catch (e) {
      return null;
    }
  }

  /// Nette afsluiting: luisteraar dicht en het socketbestand weg. Een crash
  /// laat het bestand achter; [becomePrimary] ruimt dat bij de volgende start.
  Future<void> dispose() async {
    final server = _server;
    if (server == null) return;
    _server = null;
    await server.close();
    try {
      await File((await _socketPath)!).delete();
    } catch (e) {
      // Bestaat het niet meer, dan is het doel al bereikt; een volgende start
      // ruimt een eventueel restant alsnog via becomePrimary.
    }
  }
}

/// De bewaker die `main()` verwerft, voor de shell om aan te hangen. `null`
/// op web, op niet-Linux, en in de beamer- en tweede-starter-paden — alleen de
/// primaire van de hoofdapp leeft hier.
SingleInstanceGuard? activeSingleInstance;

/// Leest één geframed bericht: `aantal\n` en daarna precies zoveel regels.
Future<List<String>> _readFramedPaths(Socket connection) async {
  final buffer = StringBuffer();
  final incoming = _decodeLimited(
    connection,
    SingleInstanceGuard._maxFrameBytes,
  );
  await for (final chunk in incoming) {
    buffer.write(chunk);
    final parsed = _framedPaths(buffer.toString());
    if (parsed != null) return parsed;
  }
  throw const FormatException('Incomplete launch frame');
}

/// `null` zolang de kop of de beloofde regels er nog niet zijn.
List<String>? _framedPaths(String text) {
  final nl = text.indexOf('\n');
  if (nl < 0) return null;
  final count = int.tryParse(text.substring(0, nl));
  if (count == null || count < 0 || count > SingleInstanceGuard._maxPaths) {
    throw const FormatException('Invalid launch path count');
  }
  if (count == 0) return const [];
  final lines = text.substring(nl + 1).split('\n');
  if (lines.length < count + 1) return null;
  return [
    for (final line in lines.take(count))
      if (looksLikeDeckLaunchArg(line.trim())) line.trim(),
  ];
}

Stream<String> _decodeLimited(Socket socket, int maxBytes) {
  var used = 0;
  return utf8.decoder.bind(
    socket.map<List<int>>((chunk) {
      used += chunk.length;
      if (used > maxBytes) {
        throw const FormatException('Launch frame too large');
      }
      return chunk;
    }),
  );
}
