// Part of the file_service library — see file_service.dart.
// The one-click audit dossier (PENTEST_MIAUW §10.11): the standalone `.ocideck`
// package plus an audit-dossier index and an optional rendered report, sealed
// into the same AES-256 zip. Split out for navigability; imports live in the
// main library file. The index Markdown (audit_dossier.dart) and any PDF bytes
// are produced in the UI layer and passed in, so this extension stays IO-light
// and reuses the package builder + encryptor verbatim.
part of '../file_service.dart';

/// Package member name of the audit-dossier index Markdown.
const String kAuditDossierFileName = 'AUDIT_DOSSIER.md';

extension FileServiceDossier on FileService {
  /// Package member name of the optional rendered report inside the dossier.
  static const String dossierReportName = 'report.pdf';

  Future<Archive> _buildDossierArchive(
    Deck deck, {
    required String dossierIndex,
    List<int>? reportPdf,
  }) async {
    // Start from the ordinary package (report `.md` + all assets + evidence
    // images) and add the audit sidecars.
    final archive = await _buildPackageArchive(deck);
    final index = utf8.encode(dossierIndex);
    archive.add(ArchiveFile(kAuditDossierFileName, index.length, index));
    if (reportPdf != null && reportPdf.isNotEmpty) {
      archive.add(ArchiveFile(dossierReportName, reportPdf.length, reportPdf));
    }
    return archive;
  }

  /// Build the bytes of a one-click audit dossier (see [exportDossier]). With a
  /// non-empty [password] every member is WinZip-AES-256 encrypted, exactly like
  /// [buildPackageBytes]; off web the zip runs in an isolate.
  Future<Uint8List> buildDossierBytes(
    Deck deck, {
    required String dossierIndex,
    List<int>? reportPdf,
    String? password,
  }) async {
    final archive = await _buildDossierArchive(
      deck,
      dossierIndex: dossierIndex,
      reportPdf: reportPdf,
    );
    final pw = (password != null && password.isNotEmpty) ? password : null;
    if (kIsWeb) return ZipEncoder(password: pw).encodeBytes(archive);
    return Isolate.run(() => ZipEncoder(password: pw).encodeBytes(archive));
  }

  /// Write an audit dossier to [destPath] (desktop). Mirrors [exportPackage].
  Future<void> exportDossier(
    Deck deck,
    String destPath, {
    required String dossierIndex,
    List<int>? reportPdf,
    String? password,
  }) async {
    final bytes = await buildDossierBytes(
      deck,
      dossierIndex: dossierIndex,
      reportPdf: reportPdf,
      password: password,
    );
    await writeBytesAtomic(File(destPath), bytes);
  }

  /// Web: build the dossier in memory and offer it to the browser as a download.
  /// Returns the filename used. Mirrors [downloadPackage] with a dossier-distinct
  /// name.
  Future<String> downloadDossier(
    Deck deck, {
    required String dossierIndex,
    List<int>? reportPdf,
    String? password,
  }) async {
    final bytes = await buildDossierBytes(
      deck,
      dossierIndex: dossierIndex,
      reportPdf: reportPdf,
      password: password,
    );
    final name =
        '${_safeName(deck.title)}_auditdossier.'
        '${FileService.packageExtension}';
    await FilePicker.saveFile(fileName: name, bytes: bytes);
    return name;
  }

  /// Desktop: ask where to write the dossier, defaulting to a dossier-distinct
  /// name. Mirrors [pickPackageDestination].
  Future<String?> pickDossierDestination(Deck deck) async {
    return FilePicker.saveFile(
      dialogTitle: _d('Auditdossier exporteren'),
      fileName:
          '${_safeName(deck.title)}_auditdossier.'
          '${FileService.packageExtension}',
    );
  }

  /// The flat, unzipped dossier members (path → bytes), so a test can assert the
  /// index + report + package assets are present without unzipping.
  @visibleForTesting
  Future<Map<String, List<int>>> buildDossierMembers(
    Deck deck, {
    required String dossierIndex,
    List<int>? reportPdf,
  }) async {
    final archive = await _buildDossierArchive(
      deck,
      dossierIndex: dossierIndex,
      reportPdf: reportPdf,
    );
    return {
      for (final f in archive.files)
        if (f.isFile) f.name: f.content,
    };
  }
}
