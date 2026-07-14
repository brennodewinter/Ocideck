import '../../models/local_cve_record.dart';
import '../../models/local_cve_status.dart';

/// De lokale CVE-database, zoals de UI hem ziet. Geen `dart:io` hier: dit
/// bestand moet ook op het web compileren, waar de hele functie niet bestaat.
abstract class LocalCveDatabase {
  /// False op het web: daar is geen bestandssysteem, en een download van
  /// honderden megabytes hoort niet in een browsertab.
  bool get supported;

  /// Wat er nu ligt, of null als er niets ligt.
  Future<LocalCveStats?> stats();

  /// Zoekt offline. Er gaat geen byte het apparaat uit.
  Future<List<LocalCveRecord>> search(String query, {int limit = 25});

  /// Haalt de nieuwste bulkrelease op en bouwt de index opnieuw.
  Future<LocalCveStats> build({
    required void Function(CveIngestProgress) onProgress,
    required bool Function() isCancelled,
  });

  /// Verwijdert de lokale database.
  Future<void> delete();
}
