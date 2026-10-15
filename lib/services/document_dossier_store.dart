import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/document_dossier.dart';
import '../utils/atomic_file.dart';

enum DossierIntegrityStatus { matches, changed, missing, unreadable, unsafe }

class DossierIntegrityResult {
  const DossierIntegrityResult(
    this.status, {
    this.actualSha256,
    this.checkedAt,
  });

  final DossierIntegrityStatus status;
  final String? actualSha256;
  final DateTime? checkedAt;
}

/// Owns an index of source documents; the source bytes remain in place.
class DocumentDossierStore {
  DocumentDossierStore(this.manifestFile);

  final File manifestFile;
  static const _uuid = Uuid();

  Directory get directory => manifestFile.parent;
  File get overviewFile => File(p.join(directory.path, 'overzicht.md'));

  Future<DocumentDossier> create(
    String title, {
    String description = '',
  }) async {
    if (await manifestFile.exists()) {
      throw const FileSystemException('Dossier bestaat al');
    }
    final now = DateTime.now().toUtc();
    final dossier = DocumentDossier(
      title: title,
      description: description,
      entries: const [],
      createdAt: now,
      updatedAt: now,
    );
    await save(dossier);
    return dossier;
  }

  Future<DocumentDossier> load() async {
    await _rejectManifestLink();
    final decoded = jsonDecode(await manifestFile.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Ongeldig dossierformaat');
    }
    return DocumentDossier.fromJson(decoded);
  }

  Future<void> save(DocumentDossier dossier) async {
    await directory.create(recursive: true);
    await _rejectManifestLink();
    if (await FileSystemEntity.type(overviewFile.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FileSystemException('Onveilig dossieroverzicht');
    }
    if (await overviewFile.exists()) {
      if (!await manifestFile.exists()) {
        throw FileSystemException(
          'Bestaand dossieroverzicht wordt niet overschreven',
          overviewFile.path,
        );
      }
      final previous = await load();
      if (await overviewFile.readAsString() != _overviewMarkdown(previous)) {
        throw FileSystemException(
          'Dossieroverzicht is handmatig gewijzigd; bewaar die wijzigingen eerst',
          overviewFile.path,
        );
      }
    }
    final ids = <String>{};
    final manualNumbers = <int>{};
    for (final entry in dossier.entries) {
      if (!ids.add(entry.id) || !_validRelativePath(entry.relativePath)) {
        throw const FormatException('Ongeldige dossierverwijzing');
      }
      if (entry.sourcePath != null && !p.isAbsolute(entry.sourcePath!)) {
        throw const FormatException('Ongeldig absoluut bronpad');
      }
      if (entry.sourceRelativePath != null &&
          !_validRelativePath(entry.sourceRelativePath!)) {
        throw const FormatException('Ongeldig relatief bronpad');
      }
      if (entry.documentDate != null &&
          !DossierEntry.validDocumentDate(entry.documentDate!)) {
        throw const FormatException('Ongeldige documentdatum');
      }
      if (entry.numberOverride case final int number) {
        if (number < 1 || !manualNumbers.add(number)) {
          throw const FormatException('Dubbel of ongeldig dossiernummer');
        }
      }
    }
    final temp = File('${manifestFile.path}.${_uuid.v4()}.tmp');
    final overviewTemp = File('${overviewFile.path}.${_uuid.v4()}.tmp');
    try {
      await writeStringAtomic(
        temp,
        '${const JsonEncoder.withIndent('  ').convert(dossier.toJson())}\n',
      );
      await writeStringAtomic(overviewTemp, _overviewMarkdown(dossier));
      await temp.rename(manifestFile.path);
      await overviewTemp.rename(overviewFile.path);
    } finally {
      if (await temp.exists()) await temp.delete();
      if (await overviewTemp.exists()) await overviewTemp.delete();
    }
  }

  /// Indexes source bytes in place; no document or related assets are copied.
  Future<DocumentDossier> addFile(
    DocumentDossier dossier,
    File source, {
    String? title,
  }) async {
    final realSource = await source.resolveSymbolicLinks();
    if (await FileSystemEntity.type(realSource) != FileSystemEntityType.file) {
      throw FileSystemException('Bron is geen bestand', source.path);
    }
    final id = _uuid.v4();
    final root = await directory.resolveSymbolicLinks();
    final nearby = p.isWithin(root, realSource);
    final relative = nearby ? p.relative(realSource, from: root) : null;
    final now = DateTime.now().toUtc();
    final digest = await _hash(File(realSource));
    final bytes = await File(realSource).length();
    final entry = DossierEntry(
      id: id,
      title: title?.trim().isNotEmpty == true
          ? title!.trim()
          : p.basenameWithoutExtension(realSource),
      relativePath: relative == null
          ? p.basename(realSource)
          : p.posix.joinAll(p.split(relative)),
      sha256: digest,
      sourcePath: realSource,
      sourceRelativePath: relative == null
          ? null
          : p.posix.joinAll(p.split(relative)),
      originalName: p.basename(realSource),
      sizeBytes: bytes,
      checkedAt: now,
    );
    final updated = dossier.copyWith(
      entries: [...dossier.entries, entry],
      updatedAt: now,
    );
    await save(updated);
    return updated;
  }

  /// Returns null for a missing or unsafe path. This must be used before opening.
  Future<String?> resolvedPath(DossierEntry entry) async {
    if (!_validRelativePath(entry.relativePath)) return null;
    if (entry.sourcePath != null) {
      if (!p.isAbsolute(entry.sourcePath!)) return null;
      final sourcePath = entry.sourceRelativePath == null
          ? p.normalize(entry.sourcePath!)
          : p.normalize(
              p.join(
                await directory.resolveSymbolicLinks(),
                p.fromUri(entry.sourceRelativePath!),
              ),
            );
      if (entry.sourceRelativePath != null &&
          (!_validRelativePath(entry.sourceRelativePath!) ||
              !p.isWithin(
                await directory.resolveSymbolicLinks(),
                sourcePath,
              ))) {
        return null;
      }
      try {
        final realFile = await File(sourcePath).resolveSymbolicLinks();
        if (realFile != sourcePath ||
            await FileSystemEntity.type(realFile) !=
                FileSystemEntityType.file) {
          return null;
        }
        return realFile;
      } on FileSystemException {
        return null;
      }
    }
    final root = p.canonicalize(directory.absolute.path);
    final candidate = p.normalize(p.join(root, p.fromUri(entry.relativePath)));
    if (!p.isWithin(root, candidate)) return null;
    try {
      final realRoot = await directory.resolveSymbolicLinks();
      final realFile = await File(candidate).resolveSymbolicLinks();
      if (!p.isWithin(realRoot, realFile)) return null;
      if (await FileSystemEntity.type(realFile) != FileSystemEntityType.file) {
        return null;
      }
      return realFile;
    } on FileSystemException {
      return null;
    }
  }

  Future<DossierIntegrityResult> verify(DossierEntry entry) async {
    final checkedAt = DateTime.now().toUtc();
    if (!_validRelativePath(entry.relativePath)) {
      return DossierIntegrityResult(
        DossierIntegrityStatus.unsafe,
        checkedAt: checkedAt,
      );
    }
    final candidate =
        (entry.sourceRelativePath == null
            ? entry.sourcePath
            : p.join(directory.path, entry.sourceRelativePath!)) ??
        p.normalize(
          p.join(directory.absolute.path, p.fromUri(entry.relativePath)),
        );
    if (entry.sourcePath == null &&
        !p.isWithin(directory.absolute.path, candidate)) {
      return DossierIntegrityResult(
        DossierIntegrityStatus.unsafe,
        checkedAt: checkedAt,
      );
    }
    if (!await File(candidate).exists()) {
      return DossierIntegrityResult(
        DossierIntegrityStatus.missing,
        checkedAt: checkedAt,
      );
    }
    final path = await resolvedPath(entry);
    if (path == null) {
      return DossierIntegrityResult(
        DossierIntegrityStatus.unsafe,
        checkedAt: checkedAt,
      );
    }
    try {
      final actual = await _hash(File(path));
      return DossierIntegrityResult(
        actual == entry.sha256
            ? DossierIntegrityStatus.matches
            : DossierIntegrityStatus.changed,
        actualSha256: actual,
        checkedAt: checkedAt,
      );
    } on FileSystemException {
      return DossierIntegrityResult(
        DossierIntegrityStatus.unreadable,
        checkedAt: checkedAt,
      );
    }
  }

  /// Records a completed check without accepting a changed source hash.
  Future<(DocumentDossier, DossierIntegrityResult)> verifyAndRecord(
    DocumentDossier dossier,
    DossierEntry entry,
  ) async {
    final index = dossier.entries.indexWhere(
      (candidate) => candidate.id == entry.id,
    );
    if (index < 0) throw ArgumentError.value(entry.id, 'entry.id');
    final result = await verify(entry);
    final entries = [...dossier.entries];
    entries[index] = entry.copyWith(checkedAt: result.checkedAt);
    final updated = dossier.copyWith(
      entries: entries,
      updatedAt: DateTime.now().toUtc(),
    );
    await _saveManifestOnly(updated);
    return (updated, result);
  }

  Future<void> _saveManifestOnly(DocumentDossier dossier) async {
    await _rejectManifestLink();
    final temp = File('${manifestFile.path}.${_uuid.v4()}.tmp');
    try {
      await writeStringAtomic(
        temp,
        '${const JsonEncoder.withIndent('  ').convert(dossier.toJson())}\n',
      );
      await temp.rename(manifestFile.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  /// Updates the reference only when the caller explicitly asks to accept bytes.
  Future<DocumentDossier> refreshReference(
    DocumentDossier dossier,
    String entryId, {
    String? expectedSha256,
  }) async {
    final index = dossier.entries.indexWhere((entry) => entry.id == entryId);
    if (index < 0) throw ArgumentError.value(entryId, 'entryId');
    final entry = dossier.entries[index];
    final result = await verify(entry);
    if (result.actualSha256 == null) {
      throw FileSystemException(
        'Bijlage kan niet worden gecontroleerd',
        entry.relativePath,
      );
    }
    if (expectedSha256 != null && result.actualSha256 != expectedSha256) {
      throw StateError('Bijlage is opnieuw gewijzigd sinds de controle');
    }
    final entries = [...dossier.entries];
    final now = DateTime.now().toUtc();
    final realPath = await resolvedPath(entry);
    entries[index] = entry.copyWith(
      sha256: result.actualSha256,
      sizeBytes: realPath == null ? null : await File(realPath).length(),
      checkedAt: now,
      hashHistory: result.actualSha256 == entry.sha256
          ? entry.hashHistory
          : [
              ...entry.hashHistory,
              DossierHashRevision(sha256: entry.sha256, recordedAt: now),
            ],
    );
    final updated = dossier.copyWith(entries: entries, updatedAt: now);
    await save(updated);
    return updated;
  }

  Future<void> _rejectManifestLink() async {
    if (await FileSystemEntity.type(manifestFile.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FileSystemException('Onveilig dossierbestand');
    }
  }

  static bool _validRelativePath(String path) {
    if (path.isEmpty ||
        path.contains('\\') ||
        path.contains('\u0000') ||
        p.posix.isAbsolute(path) ||
        p.posix.normalize(path) != path) {
      return false;
    }
    return !p.posix.split(path).any((part) => part == '..' || part == '.');
  }

  static Future<String> _hash(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  static String _overviewMarkdown(DocumentDossier dossier) {
    final buffer = StringBuffer()
      ..writeln('# ${_markdownText(dossier.title)}')
      ..writeln()
      ..writeln('## Inhoud')
      ..writeln();
    if (dossier.entries.isEmpty) {
      buffer.writeln('Nog geen documenten toegevoegd.');
    }
    for (var index = 0; index < dossier.entries.length; index++) {
      final entry = dossier.entries[index];
      final link = entry.sourcePath == null || entry.sourceRelativePath != null
          ? Uri(pathSegments: p.posix.split(entry.relativePath)).toString()
          : Uri.file(entry.sourcePath!).toString();
      buffer.writeln(
        '${dossier.numberFor(index)}. [${_markdownText(entry.title)}]($link)',
      );
      if (entry.description.trim().isNotEmpty) {
        buffer.writeln('   ${_markdownText(entry.description.trim())}');
      }
      if (entry.documentDate != null) {
        buffer.writeln('   Datum: ${entry.documentDate}');
      }
      if (entry.author.trim().isNotEmpty) {
        buffer.writeln('   Opsteller: ${_markdownText(entry.author.trim())}');
      }
      buffer
        ..writeln('   SHA-256: `${entry.sha256}`')
        ..writeln();
    }
    return buffer.toString();
  }

  static String _markdownText(String text) => text
      .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
      .replaceAllMapped(
        RegExp(r'[\\`*_{}\[\]<>()#+.!|~-]'),
        (match) => '\\${match.group(0)}',
      );
}
