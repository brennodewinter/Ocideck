import 'dart:io';

/// Ruimt een test-tempmap op, ook op Windows waar een net afgesloten
/// git-subproces (of de virusscanner) de bestandshandle nog even vasthoudt.
///
/// ── Waarom dit bestaat ──
///
/// De git-zware suites doen echte `git`-subprocessen in `Directory.systemTemp`
/// en ruimen die in hun `tearDown` op met `deleteSync(recursive: true)`. Op de
/// Windows-CI faalt dat intermitterend met errno 32 — *"The process cannot
/// access the file because it is being used by another process"* — omdat git de
/// pack-bestanden of de virusscanner de map nog een fractie langer open heeft
/// dan de test leeft. Eén poging is dan te vroeg; even later is de handle los.
///
/// Deze hulp probeert het daarom een paar keer opnieuw met een korte pauze (het
/// bekende Windows-patroon), en geeft ná de laatste poging op zónder te gooien.
/// Dat laatste is bewust: een achtergebleven map in de wegwerp-`systemTemp` van
/// een CI-runner is onschadelijk, maar een `tearDown` die gooit markeert een
/// test die zélf slaagde alsnog als rood — precies de flakiness die #933
/// wegneemt. Op elk ander platform slaagt de eerste poging en is dit een
/// gewone `deleteSync`.
///
/// [deleteOnce] is er alleen voor de test die de herhaal-lus zonder een echte
/// Windows-vergrendeling moet kunnen bewijzen; laat hem in productiegebruik weg.
Future<void> deleteTempDir(
  Directory dir, {
  int attempts = 5,
  Duration retryDelay = const Duration(milliseconds: 100),
  void Function()? deleteOnce,
}) async {
  final delete =
      deleteOnce ??
      () {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      };
  for (var attempt = 1; ; attempt++) {
    try {
      delete();
      return;
    } on FileSystemException {
      if (attempt >= attempts) return; // opgegeven — zie de doc hierboven
      await Future<void>.delayed(retryDelay);
    }
  }
}
