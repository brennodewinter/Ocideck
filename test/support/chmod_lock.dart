import 'dart:io';

/// Meet of een chmod-slot werkelijk houdt in plaats van dat te veronderstellen.
///
/// `chmod 555`/`000` houdt root niet tegen en de CI-containers draaien als
/// root — daar slaagt de "mislukte" schrijf- of leesactie gewoon. Een test die
/// zo'n scenario toetst moet dan `markTestSkipped` gebruiken in plaats van
/// vals-rood te melden; op een ontwikkelaarsmachine draait hij onverkort.
///
/// `schrijven`: [pad] is een map die geen bestand meer mag aannemen
/// (`chmod 555`). Anders moet [pad] — map of bestand — onleesbaar zijn.
bool chmodLockHoudt(String pad, {bool schrijven = true}) {
  try {
    if (schrijven) {
      final probe = File('$pad/.chmod-probe')..writeAsBytesSync(const []);
      probe.deleteSync();
    } else if (FileSystemEntity.isDirectorySync(pad)) {
      Directory(pad).listSync();
    } else {
      File(pad).readAsBytesSync();
    }
    return false;
  } on FileSystemException {
    return true;
  }
}
