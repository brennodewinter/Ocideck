import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/log.dart';
import '../export_metadata.dart' show kOciDeckVersion;
import 'log_file.dart';
import 'ui_stall_watch.dart';

/// Het logbestand van een desktopbuild en wat erbij hoort (#2618): de
/// sessiemarkering, de systeemregel aan het begin van elke sessie en de
/// stallmelder.
///
/// Niets hiervan gaat het netwerk op. Het bestand blijft op deze computer tot
/// de gebruiker het zelf deelt, via "Logmap openen" of "Diagnose kopiëren" in
/// Instellingen → Over OciDeck.
abstract final class Diagnostics {
  /// De submap van de app-supportmap waarin de logbestanden staan.
  static const logDirName = 'logs';

  /// Hoeveel regels "Diagnose kopiëren" meeneemt.
  static const reportLines = 200;

  static LogFile? _log;
  static UiStallWatch? _stallWatch;

  /// Zet het logbestand op. [name] scheidt het hoofdvenster (`ocideck`) van het
  /// beamervenster (`beamer`): dat draait in een eigen engine en zou anders om
  /// hetzelfde bestand heen roteren. Alleen het hoofdvenster houdt een
  /// sessiemarkering bij ([session]).
  static Future<void> start({
    String name = 'ocideck',
    bool session = true,
  }) async {
    if (kIsWeb) return;
    final LogFile log;
    try {
      final support = await getApplicationSupportDirectory();
      log = LogFile.open(
        Directory(p.join(support.path, logDirName)),
        name: name,
        sessionInfo: session
            ? 'gestart ${DateTime.now().toIso8601String()}, '
                  'versie $kOciDeckVersion'
            : null,
      );
    } catch (e) {
      logWarning('Diagnostics: geen logbestand', e);
      return;
    }
    _log = log;
    installLogSink(log);
    logInfo('sessie: ${_systemLine()}');
    final previous = log.previousSession;
    if (previous != null) {
      logWarning(
        'vorige sessie ($previous) is niet netjes afgesloten: vastgelopen, '
        'geforceerd beëindigd of met de computer mee uitgezet',
      );
    }
  }

  /// Het eerste frame staat: vanaf nu schrijft het logbestand op de
  /// achtergrond, en de stallmelder begint te meten.
  static void firstFrameShown() {
    final log = _log;
    if (log == null) return;
    log.writeInBackground();
    (_stallWatch ??= UiStallWatch()).start();
  }

  /// De map met de logbestanden, of `null` zonder logbestand (web, of een
  /// app-supportmap die niet beschikbaar was).
  static Directory? get logDirectory => _log?.directory;

  /// De tekst voor "Diagnose kopiëren": versie, systeem en de laatste
  /// [reportLines] regels van het log.
  ///
  /// Markdown, omdat hij bedoeld is om in een issue te plakken: de logregels in
  /// een codeblok, zodat de tracker ze niet als opmaak leest. Via het klembord
  /// en niet via een vooringevulde issue-URL — dan zou het log over het netwerk
  /// gaan voordat de gebruiker het heeft gezien.
  static Future<String> report() async {
    final out = StringBuffer()
      ..writeln('**OciDeck-diagnose**')
      ..writeln()
      ..writeln('- ${_systemLine()}')
      ..writeln('- Dart ${Platform.version}')
      ..writeln();
    final log = _log;
    if (log == null) {
      out.writeln('(geen logbestand)');
      return out.toString();
    }
    out
      ..writeln('````text')
      ..writeAll(await log.tail(reportLines), '\n')
      ..writeln()
      ..writeln('````');
    return out.toString();
  }

  static String _systemLine() {
    final mode = kReleaseMode ? '' : (kProfileMode ? ' (profile)' : ' (debug)');
    return 'OciDeck $kOciDeckVersion$mode op ${Platform.operatingSystem} '
        '${Platform.operatingSystemVersion}, '
        '${Platform.numberOfProcessors} processorkernen';
  }

  /// Alleen voor tests: zet [log] neer zoals [start] dat zou doen.
  @visibleForTesting
  static void debugUse(LogFile? log) {
    _stallWatch?.stop();
    _stallWatch = null;
    _log = log;
    installLogSink(log);
  }
}
