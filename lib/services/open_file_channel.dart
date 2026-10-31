import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';
import '../platform/native_window.dart' show focusPrimaryWindow;
import '../utils/log.dart';
import 'single_instance.dart';

/// Method channel gedeeld met de macOS-host: Finder-"Open met" binnenkomend, en
/// de filterloze bestandskiezer uitgaand. Zie `macos/Runner/AppDelegate.swift`.
const MethodChannel kOpenFileChannel = MethodChannel('ocideck/open_file');

/// Opent op macOS een NSOpenPanel zonder typefilter.
///
/// `file_picker`'s `FileType.any` zet géén `allowedContentTypes`. macOS kan dan
/// een onthouden filter uit een eerdere sessie laten staan, waardoor `.md`-
/// bestanden grijs en onaantikbaar worden in het systeemvenster. De native
/// kant wist die filter expliciet (lege `allowedContentTypes` = alle typen).
///
/// Belangrijk: de Openen-dialoog moet *vóór* deze call dicht zijn. Een
/// `NSOpenPanel` onder een open Flutter-`AlertDialog` grijst `.md` alsnog.
///
/// Levert het gekozen pad, of `null` bij annuleren. Op niet-macOS altijd
/// `null`. [MissingPluginException] (oude build zonder native handler) wordt
/// doorgegeven — de aanroeper mag dan op file_picker terugvallen. Andere fouten
/// worden gelogd en als annuleren behandeld.
Future<String?> pickUnfilteredMacFile({
  String? dialogTitle,
  String? initialDirectory,
}) async {
  final picked = await pickUnfilteredMacFiles(
    dialogTitle: dialogTitle,
    initialDirectory: initialDirectory,
  );
  return picked.isEmpty ? null : picked.first;
}

/// De meervoudige variant van [pickUnfilteredMacFile]: hetzelfde filterloze
/// paneel, maar met `allowsMultipleSelection`, zodat de gebruiker een stapel
/// bestanden in één keer kan aanwijzen. Levert de paden in de volgorde die het
/// paneel teruggaf, of een lege lijst bij annuleren en op elk ander platform.
///
/// De native kant levert altijd een lijst — ook voor één bestand — zodat er
/// maar één vorm over het kanaal reist.
Future<List<String>> pickUnfilteredMacFiles({
  String? dialogTitle,
  String? initialDirectory,
  bool allowsMultiple = false,
}) async {
  if (kIsWeb || !Platform.isMacOS) return const [];
  try {
    final paths = await kOpenFileChannel.invokeListMethod<String>('pickFile', {
      'dialogTitle': dialogTitle,
      'initialDirectory': initialDirectory,
      'allowsMultiple': allowsMultiple,
    });
    return paths ?? const [];
  } on MissingPluginException {
    rethrow;
  } catch (e) {
    logWarning('pickUnfilteredMacFile failed', e);
    return const [];
  }
}

/// Opent op macOS een `NSSavePanel` zonder typefilter en levert het gekozen
/// pad — het opslaan-spiegelbeeld van [pickUnfilteredMacFile].
///
/// `file_picker.saveFile` gebruikt op macOS `NSSavePanel.beginSheetModal` op
/// het Flutter-venster. Die sheet erft de `CFBundleDocumentTypes`-filter van de
/// app en verschijnt niet betrouwbaar — precies de reden dat [pickUnfilteredMacFile]
/// een eigen `runModal`-kiezer gebruikt. Het opslaan-pad kreeg die behandeling
/// voorheen niet, waardoor "Kies bestandsnaam…" na de bestemmingsdialoog niets
/// deed: de sheet verscheen niet, `saveFile` keerde stil terug naar `null`, en
/// `saveAs` rapporteerde `false` zonder melding.
///
/// De native kant schrijft geen bytes — net als `file_picker.saveFile` op
/// desktop levert deze functie alleen het pad; de aanroeper schrijft zelf.
///
/// Belangrijk: de bestemmingsdialoog moet *vóór* deze call dicht zijn, om
/// dezelfde reden als bij [pickUnfilteredMacFile].
///
/// Levert het gekozen pad, of `null` bij annuleren. Op niet-macOS altijd
/// `null`. [MissingPluginException] (oude build zonder native handler) wordt
/// doorgegeven — de aanroeper mag dan op `file_picker` terugvallen. Andere
/// fouten worden gelogd en als annuleren behandeld.
Future<String?> saveMacFile({
  String? dialogTitle,
  String? fileName,
  String? initialDirectory,
}) async {
  if (kIsWeb || !Platform.isMacOS) return null;
  try {
    return await kOpenFileChannel.invokeMethod<String>('saveFile', {
      'dialogTitle': dialogTitle,
      'fileName': fileName,
      'initialDirectory': initialDirectory,
    });
  } on MissingPluginException {
    rethrow;
  } catch (e) {
    logWarning('saveMacFile failed', e);
    return null;
  }
}

/// Receives file paths from the macOS host when the user opens a `.md` or
/// `.ocideck` file via Finder (double-click / "Open With"). See
/// `macos/Runner/AppDelegate.swift` for the native side.
///
/// Op Windows levert hetzelfde kanaal de paden die een tweede starter via
/// `WM_COPYDATA` naar het draaiende exemplaar stuurt — zie `main.cpp` en
/// `flutter_window.cpp` in `windows/runner` (#2627).
///
/// On [start] it drains any files the app was launched with (cold start) and
/// then listens for files opened while the app is already running (warm start).
class OpenFileChannel {
  /// Called with one or more file paths to open. Routing (markdown vs package)
  /// is the caller's responsibility.
  final Future<void> Function(List<String> paths) onOpenFiles;

  OpenFileChannel(this.onOpenFiles);

  Future<void> start() async {
    // kIsWeb eerst: Platform.isMacOS is op web een dart:io-stub die gooit.
    // Linux: geen hostkanaal maar de enkel-exemplaar-socket uit main() (#2656)
    // — dezelfde onOpenFiles-route als WM_COPYDATA op Windows.
    if (!kIsWeb && Platform.isLinux) {
      // Elk bericht van een tweede starter, ook zonder pad, haalt dit
      // venster naar voren. Zonder dat deed een start via het menu niets
      // zichtbaars zolang de eerste app al draaide (#2679).
      activeSingleInstance?.onActivate = () {
        unawaited(focusPrimaryWindow());
      };
      activeSingleInstance?.onFiles = (paths) {
        unawaited(onOpenFiles(paths));
      };
      return;
    }
    // macOS: Finder-open-events; Windows: WM_COPYDATA van een tweede starter.
    if (kIsWeb || !(Platform.isMacOS || Platform.isWindows)) return;
    await activate();
  }

  /// De kanaalkant zonder de platformpoort: handler registreren en de
  /// koude-startbestanden leegtrekken. Apart van [start], zodat de logica op
  /// elk platform onder test staat — de poort hierboven bepaalt alleen wáár
  /// hij echt aan gaat.
  @visibleForTesting
  Future<void> activate() async {
    kOpenFileChannel.setMethodCallHandler(_handle);
    try {
      final launch = await kOpenFileChannel.invokeMethod<List<dynamic>>(
        'getLaunchFiles',
      );
      final paths = _stringList(launch);
      if (paths.isNotEmpty) await onOpenFiles(paths);
    } on MissingPluginException {
      // No native handler (e.g. running an older build): nothing to do.
    } catch (e) {
      logWarning('OpenFileChannel.start: getLaunchFiles failed', e);
    }
  }

  Future<dynamic> _handle(MethodCall call) async {
    if (call.method == 'openFiles') {
      final paths = _stringList(call.arguments);
      if (paths.isNotEmpty) await onOpenFiles(paths);
    }
    return null;
  }

  List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<String>().toList();
  }
}
