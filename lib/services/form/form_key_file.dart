// Een bestand met een geheim erin (FORM_INTAKE.md §5.9: de age-identiteit is te bewaren als
// bestand, zodat een verzegeld pakket ook zonder OciDeck opent).
//
// Twee dingen maken dit anders dan `writeAsString`:
//
// * **Rechten eerst, geheim daarna.** Het bestand wordt gemaakt, krijgt zijn beperkte rechten,
//   en pas dán komt het geheim erin. Een bestand dat even met de standaardrechten bestond, was
//   even voor elke lokale gebruiker leesbaar.
// * **Een bestaand bestand blijft heel tot het nieuwe af is.** Er wordt naast het doel geschreven
//   en daarna verplaatst, zoals `writeBytesAtomic` doet (de conventiepoort eist dat voor elk
//   bestand); dat helper kan hier niet, want zijn tijdelijke bestand krijgt de standaardrechten.
library;

import 'dart:io';

/// Schrijft [text] naar [path] in een bestand dat alleen de eigenaar mag lezen (op systemen
/// met bestandsrechten). Een bestaand bestand wordt vervangen door een nieuw, niet
/// overschreven: de rechten van het oude doen er niet toe en het oude blijft staan als het
/// schrijven mislukt. Werpt [FileSystemException] als het niet lukt, en laat dan geen bestand
/// met het geheim achter.
Future<void> writeSecretFile(String path, String text) async {
  final target = File(path);
  final temp = File('$path.${DateTime.now().microsecondsSinceEpoch}.tmp');
  try {
    await temp.create(exclusive: true);
    if (!Platform.isWindows) {
      final result = await Process.run('chmod', ['600', temp.path]);
      if (result.exitCode != 0) {
        throw FileSystemException('rechten niet te beperken', path);
      }
    }
    final out = await temp.open(mode: FileMode.write);
    try {
      await out.writeString(text);
      await out.flush();
    } finally {
      await out.close();
    }
    await _replace(temp, target);
  } on FileSystemException {
    if (await temp.exists()) await temp.delete();
    rethrow;
  }
}

/// Verplaatst [temp] op [target]. Op Windows weigert `rename` een bestaand doel: dan eerst
/// het doel weg, zoals `writeBytesAtomic`.
Future<void> _replace(File temp, File target) async {
  try {
    await temp.rename(target.path);
  } on FileSystemException {
    if (!await target.exists()) rethrow;
    await target.delete();
    await temp.rename(target.path);
  }
}
