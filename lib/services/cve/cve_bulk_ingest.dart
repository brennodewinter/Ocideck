import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import '../../models/local_cve_status.dart';
import 'cve_record_parser.dart';
import 'local_cve_index.dart';

/// Waar het bulkarchief vandaan komt. Geïnjecteerd, zodat de tests de hele
/// keten (ontdekken → downloaden → uitpakken → indexeren) kunnen draaien met
/// een archiefje van een paar kilobyte in plaats van 550 MB.
abstract class CveBulkTransport {
  /// Haalt JSON op (de release-metadata).
  Future<String> getJson(Uri url);

  /// Streamt [url] naar [destination]. Meldt voortgang; gooit bij afbreken.
  Future<void> download(
    Uri url,
    File destination, {
    required void Function(int received, int total) onProgress,
    required bool Function() isCancelled,
  });
}

/// Bouwt de lokale CVE-database uit de bulkrelease van CVE List V5.
///
/// De vorm van die release bepaalt de hele opzet, en is niet wat je zou raden:
///
///  * De asset heet naar de dag (`2026-07-14_all_CVEs_at_midnight.zip.zip`), dus
///    er ís geen vaste URL — hij moet via de releases-API opgezocht worden.
///  * Het is een zip ín een zip: de buitenste bevat één bestand, `cves.zip`.
///    Die moet eerst naar schijf, want inflaten in het geheugen kost ruim een
///    gigabyte.
///  * Pas in de binnenste zitten de ~300.000 losse `CVE-….json`-bestanden.
///
/// Daarom loopt alles via schijf en per record: op geen enkel moment staat de
/// hele corpus in het geheugen.
class CveBulkIngest {
  final CveBulkTransport transport;
  final LocalCveIndex index;

  /// Waar de tijdelijke archieven landen. Worden altijd opgeruimd.
  final Directory workDirectory;

  /// De releases-API van CVE List V5.
  final Uri releaseApi;

  /// Herkent de asset met álle CVE's (niet de dagelijkse delta, die klein is
  /// maar onvolledig).
  static final RegExp assetPattern = RegExp(
    r'_all_CVEs_at_midnight\.zip\.zip$',
  );

  /// Bovengrens per record. Een enkel CVE-bestand is kilobytes; alles daarboven
  /// is geen record maar een probleem (zip-bom).
  static const maxRecordBytes = 4 * 1024 * 1024;

  CveBulkIngest({
    required this.transport,
    required this.index,
    required this.workDirectory,
    Uri? releaseApi,
  }) : releaseApi =
           releaseApi ??
           Uri.parse(
             'https://api.github.com/repos/CVEProject/cvelistV5/releases/latest',
           );

  /// De hele keten. [onProgress] loopt door de vier fasen; [isCancelled] wordt
  /// tussen de stappen én tijdens de download gepolst.
  Future<LocalCveStats> run({
    required void Function(CveIngestProgress) onProgress,
    required bool Function() isCancelled,
    DateTime? now,
  }) async {
    workDirectory.createSync(recursive: true);
    final outer = File('${workDirectory.path}/cvelist-outer.zip');
    final inner = File('${workDirectory.path}/cvelist-inner.zip');

    try {
      onProgress(const CveIngestProgress(phase: CveIngestPhase.discovering));
      final release = await _latestRelease();
      _throwIfCancelled(isCancelled);

      onProgress(
        CveIngestProgress(
          phase: CveIngestPhase.downloading,
          total: release.size,
        ),
      );
      await transport.download(
        release.url,
        outer,
        onProgress: (received, total) => onProgress(
          CveIngestProgress(
            phase: CveIngestPhase.downloading,
            received: received,
            total: total > 0 ? total : release.size,
          ),
        ),
        isCancelled: isCancelled,
      );
      _throwIfCancelled(isCancelled);

      onProgress(const CveIngestProgress(phase: CveIngestPhase.extracting));
      _extractInnerZip(outer, inner);
      _throwIfCancelled(isCancelled);

      final records = await _buildIndex(inner, onProgress, isCancelled);
      if (records == 0) {
        throw const CveIngestException(
          CveIngestFailure.invalidArchive,
          'geen CVE-records in het archief',
        );
      }

      return await index.commit(
        release: release.tag,
        builtOn: (now ?? DateTime.now()).toIso8601String().split('T').first,
        records: records,
      );
    } on CveIngestException {
      index.discardPartial();
      rethrow;
    } on FileSystemException catch (e) {
      index.discardPartial();
      throw CveIngestException(CveIngestFailure.diskFull, e.message);
    } finally {
      // De twee archieven samen zijn ruim een gigabyte. Ze mogen niet blijven
      // liggen, ook niet als het misging.
      if (outer.existsSync()) outer.deleteSync();
      if (inner.existsSync()) inner.deleteSync();
    }
  }

  void _throwIfCancelled(bool Function() isCancelled) {
    if (isCancelled()) {
      throw const CveIngestException(CveIngestFailure.cancelled);
    }
  }

  Future<({String tag, Uri url, int size})> _latestRelease() async {
    final String body;
    try {
      body = await transport.getJson(releaseApi);
    } catch (e) {
      throw CveIngestException(CveIngestFailure.networkFailed, '$e');
    }

    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException catch (e) {
      throw CveIngestException(CveIngestFailure.networkFailed, e.message);
    }
    if (json is! Map) {
      throw const CveIngestException(CveIngestFailure.networkFailed);
    }

    final tag = (json['tag_name'] as String?) ?? '';
    final assets = json['assets'];
    if (assets is! List) {
      throw const CveIngestException(CveIngestFailure.networkFailed);
    }

    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = (asset['name'] as String?) ?? '';
      if (!assetPattern.hasMatch(name)) continue;
      final url = (asset['browser_download_url'] as String?) ?? '';
      final parsed = Uri.tryParse(url);
      if (parsed == null || !parsed.hasScheme) continue;
      return (
        tag: tag.isEmpty ? name : tag,
        url: parsed,
        size: (asset['size'] as num?)?.toInt() ?? 0,
      );
    }
    throw const CveIngestException(
      CveIngestFailure.invalidArchive,
      'de release bevat geen volledig CVE-archief',
    );
  }

  /// Pakt de enige zip ín de zip uit naar schijf. Streamt van bestand naar
  /// bestand: het inflaten in het geheugen zou een gigabyte kosten.
  void _extractInnerZip(File outer, File inner) {
    final input = InputFileStream(outer.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      ArchiveFile? nested;
      for (final file in archive.files) {
        if (file.isFile && file.name.toLowerCase().endsWith('.zip')) {
          nested = file;
          break;
        }
      }
      if (nested == null) {
        throw const CveIngestException(
          CveIngestFailure.invalidArchive,
          'geen genest zip-archief gevonden',
        );
      }
      final output = OutputFileStream(inner.path);
      try {
        nested.writeContent(output);
      } finally {
        output.closeSync();
      }
    } finally {
      input.closeSync();
    }
  }

  /// Leest de binnenste zip record voor record en schrijft de index. Nooit meer
  /// dan één CVE tegelijk in het geheugen.
  Future<int> _buildIndex(
    File inner,
    void Function(CveIngestProgress) onProgress,
    bool Function() isCancelled,
  ) async {
    index.discardPartial();
    final sink = index.openWriter();
    final input = InputFileStream(inner.path);
    var records = 0;

    try {
      final archive = ZipDecoder().decodeStream(input);
      for (final file in archive.files) {
        if (!file.isFile) continue;
        final name = file.name;
        // Alleen de CVE-records; de release draagt ook een README, een delta-map
        // en een schema mee.
        if (!name.endsWith('.json')) continue;
        if (!name.contains('CVE-')) continue;
        if (file.size > maxRecordBytes) continue;

        if (records % 2000 == 0) {
          if (isCancelled()) {
            throw const CveIngestException(CveIngestFailure.cancelled);
          }
          onProgress(
            CveIngestProgress(phase: CveIngestPhase.indexing, records: records),
          );
          // Geef de UI-lus lucht: dit loopt over 300.000 bestanden.
          await Future<void>.delayed(Duration.zero);
        }

        final bytes = file.readBytes();
        // Geef de gedecomprimeerde bytes meteen weer vrij: zonder dit houdt het
        // archief ze alle 300.000 vast en loopt het geheugen vol.
        file.clear();
        if (bytes == null) continue;

        final record = _parse(bytes);
        if (record == null) continue;

        sink.writeln(record);
        records++;
      }
      await sink.flush();
      return records;
    } finally {
      await sink.close();
      input.closeSync();
    }
  }

  /// Een stukgelopen record mag de hele bouw niet slopen: 300.000 bestanden uit
  /// een publieke bron bevatten er altijd een paar die niet zijn wat ze horen
  /// te zijn.
  String? _parse(List<int> bytes) {
    try {
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map<String, dynamic>) return null;
      return CveRecordParser.parse(json)?.toIndexLine();
    } on FormatException {
      return null;
    }
  }
}
