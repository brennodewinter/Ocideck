// De ene plek in de app die `chmod` aanroept.
//
// Dart heeft geen permissie-API; het alternatief is een FFI-binding naar libc, en dat is méér
// aanvalsoppervlak voor minder. Twee aanroepers hebben het nodig — de datamappen op Linux
// (`DiskTraces.restrictToOwner`, mode 700) en een bestand met een geheim erin
// (`writeSecretFile`, mode 600) — en samen hoeven ze maar één subproces, één
// SAST-uitzondering en één regel in de subprocesbewaker te kosten.
library;

import 'dart:io';

final RegExp _mode = RegExp(r'^[0-7]{3,4}$');

/// Zet de rechten van [path] op [mode] (octaal, bijvoorbeeld `'600'`). `true` als `chmod`
/// zegt dat het gelukt is. Werpt een [ProcessException] als er geen `chmod` is: de aanroeper
/// beslist of dat een stille mislukking is (een map die best effort wordt beperkt) of een
/// weigering (een geheim dat niet met wijde rechten mag blijven staan).
///
/// Alleen een octale modus komt door, en `--` staat voor de modus: [mode] en [path] kunnen
/// nooit een optie van `chmod` worden. Vaste argv, geen schil, geen invoer van buiten dat
/// niet eerst is gecontroleerd.
Future<bool> chmodPath(String mode, String path) async {
  if (!_mode.hasMatch(mode)) throw ArgumentError.value(mode, 'mode');
  // De SAST-regel bewaakt netwerkverkeer dat NetGuard niet ziet. `chmod` is niet
  // netwerkvaardig. De uitzondering staat bewust op déze regel en niet op dit bestand: een
  // tweede subproces hier moet wél alarm geven (zie #521).
  // nosemgrep: ocideck-subproces-buiten-de-gitlaag
  final result = await Process.run('chmod', ['--', mode, path]);
  return result.exitCode == 0;
}
