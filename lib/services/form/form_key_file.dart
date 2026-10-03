// Een bestand met een geheim erin (FORM_INTAKE.md §5.9: de age-identiteit is te bewaren als
// bestand, zodat een verzegeld pakket ook zonder OciDeck opent).
//
// Volgorde is wat dit anders maakt dan `writeAsString`: het bestand wordt gemaakt, krijgt
// zijn beperkte rechten, en pas dán komt het geheim erin. Een bestand dat even met de
// standaardrechten bestond, was even voor elke lokale gebruiker leesbaar.
library;

import 'dart:io';

/// Schrijft [text] naar [path] in een bestand dat alleen de eigenaar mag lezen (op systemen
/// met bestandsrechten). Een bestaand bestand wordt eerst beperkt en dan overschreven. Werpt
/// [FileSystemException] als het niet lukt, en laat dan geen bestand met het geheim achter.
Future<void> writeSecretFile(String path, String text) async {
  final file = File(path);
  await file.create();
  if (!Platform.isWindows) {
    final result = await Process.run('chmod', ['600', path]);
    if (result.exitCode != 0) {
      await file.delete();
      throw FileSystemException('rechten niet te beperken', path);
    }
  }
  try {
    await file.writeAsString(text, flush: true);
  } on FileSystemException {
    await file.delete();
    rethrow;
  }
}
