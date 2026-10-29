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
  SingleInstanceGuard({String? socketPath})
    : socketPath = socketPath ?? defaultSocketPath();

  final String socketPath;
  ServerSocket? _server;
  void Function(List<String> paths)? _onFiles;

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

  /// De socket waarop de primaire luistert. `$XDG_RUNTIME_DIR` is per
  /// gebruiker en op tmpfs — precies de grens die de mutex op Windows ook
  /// hanteert. Valt die weg (sommige servers/ssh zonder logind), dan
  /// `$TMPDIR` met de gebruikersnaam in de bestandsnaam.
  static String defaultSocketPath() {
    final runtimeDir = Platform.environment['XDG_RUNTIME_DIR'];
    if (runtimeDir != null && runtimeDir.isNotEmpty) {
      return p.join(runtimeDir, 'ocideck.sock');
    }
    final user = Platform.environment['USER'] ?? 'unknown';
    return p.join(Directory.systemTemp.path, 'ocideck-$user.sock');
  }

  /// `true` wanneer een primaire leefde en de paden is overgedragen — de
  /// aanroeper stopt dan zonder `runApp`. `false` = geen primaire gevonden.
  Future<bool> forwardToPrimary(List<String> paths) async {
    final Socket socket;
    try {
      socket = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
        timeout: const Duration(seconds: 2),
      );
    } catch (e) {
      // Connect geweigerd = het normale pad: geen primaire → deze starter
      // wordt zelf de primaire. Stil terugvallen is hier de bedoeling.
      return false;
    }
    try {
      socket.add(utf8.encode(paths.where(looksLikeDeckLaunchArg).join('\n')));
      await socket.flush();
    } catch (e) {
      logWarning('SingleInstanceGuard: paden doorsturen mislukt', e);
    } finally {
      await socket.close();
    }
    return true;
  }

  /// Word de primaire: bind de socket en dien inkomende paden aan [onFiles]
  /// zodra die geregistreerd is. Eén verwijder-opnieuw-bind ronde vangt het
  /// achtergelaten bestand van een gecrashte vorige sessie af. Faalt ook de
  /// tweede bind, dan loopt de app onbewaakt door — de status quo vandaag,
  /// geen reden om een bruikbare start te weigeren.
  Future<void> becomePrimary() async {
    _server = await _bind();
    if (_server == null) {
      try {
        await File(socketPath).delete();
      } catch (e) {
        logWarning('SingleInstanceGuard: stale socket wissen mislukt', e);
      }
      _server = await _bind();
    }
    if (_server == null) {
      logWarning(
        'SingleInstanceGuard: geen socket gebonden — geen enkel-exemplaar-poort',
      );
      return;
    }
    _server!.listen((connection) async {
      final body = await utf8.decoder.bind(connection).join();
      final paths = [
        for (final line in body.split('\n'))
          if (looksLikeDeckLaunchArg(line.trim())) line.trim(),
      ];
      if (paths.isEmpty) return;
      final handler = _onFiles;
      if (handler == null) {
        _pending.addAll(paths);
      } else {
        handler(paths);
      }
    });
  }

  Future<ServerSocket?> _bind() async {
    try {
      return await ServerSocket.bind(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
    } catch (e) {
      return null;
    }
  }

  /// Nette afsluiting: luisteraar dicht en het socketbestand weg. Een crash
  /// laat het bestand achter; [becomePrimary] ruimt dat bij de volgende start.
  Future<void> dispose() async {
    await _server?.close();
    try {
      await File(socketPath).delete();
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
