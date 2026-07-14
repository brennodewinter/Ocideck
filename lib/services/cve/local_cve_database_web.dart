import '../../models/local_cve_record.dart';
import '../../models/local_cve_status.dart';
import 'local_cve_database_api.dart';

/// Op het web bestaat de lokale database niet — en dat is geen tijdelijk gebrek
/// dat later ingevuld wordt. Er is geen bestandssysteem om een index van
/// honderden megabytes op te zetten, en een download van 550 MB hoort niet in
/// een browsertab. De UI verbergt de functie hier dan ook, in plaats van een
/// knop te tonen die niets kan.
const bool localCveSupported = false;

Future<LocalCveDatabase> createLocalCveDatabase() async =>
    const _UnsupportedLocalCveDatabase();

class _UnsupportedLocalCveDatabase implements LocalCveDatabase {
  const _UnsupportedLocalCveDatabase();

  @override
  bool get supported => false;

  @override
  Future<LocalCveStats?> stats() async => null;

  @override
  Future<List<LocalCveRecord>> search(String query, {int limit = 25}) async =>
      const [];

  @override
  Future<LocalCveStats> build({
    required void Function(CveIngestProgress) onProgress,
    required bool Function() isCancelled,
  }) async =>
      throw const CveIngestException(CveIngestFailure.unsupportedPlatform);

  @override
  Future<void> delete() async {}
}
