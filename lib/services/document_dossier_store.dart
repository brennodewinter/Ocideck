import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/document_dossier.dart';
import '../utils/atomic_file.dart';

enum DossierIntegrityStatus { matches, changed, missing, unreadable, unsafe }

class DossierIntegrityResult {
  const DossierIntegrityResult(this.status, {this.actualSha256});

  final DossierIntegrityStatus status;
  final String? actualSha256;
}

/// Owns one dossier index and its sibling `attachments/` directory.
class DocumentDossierStore {
  DocumentDossierStore(this.manifestFile);

  final File manifestFile;
  static const _uuid = Uuid();

  Directory get directory => manifestFile.parent;
  File get overviewFile => File(p.join(directory.path, 'overzicht.md'));

  Future<DocumentDossier> create(String title) async {
    if (await manifestFile.exists()) {
      throw const FileSystemException('Dossier bestaat al');
    }
    final now = DateTime.now().toUtc();
    final dossier = DocumentDossier(
      title: title,
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
    for (final entry in dossier.entries) {
      if (!ids.add(entry.id) || !_validRelativePath(entry.relativePath)) {
        throw const FormatException('Ongeldige dossierverwijzing');
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

  /// Copies source bytes into the dossier. The original is left untouched.
  Future<DocumentDossier> addFile(
    DocumentDossier dossier,
    File source, {
    String? title,
  }) async {
    final attachments = Directory(p.join(directory.path, 'attachments'));
    if (await FileSystemEntity.type(attachments.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FileSystemException('Onveilige bijlagenmap');
    }
    await attachments.create(recursive: true);
    final id = _uuid.v4();
    final extension = p.extension(source.path).toLowerCase();
    final name = '$id$extension';
    final destination = File(p.join(attachments.path, name));
    final temp = File('${destination.path}.tmp');
    try {
      await source.copy(temp.path);
      final digest = await _hash(temp);
      await temp.rename(destination.path);
      final entry = DossierEntry(
        id: id,
        title: title?.trim().isNotEmpty == true
            ? title!.trim()
            : p.basenameWithoutExtension(source.path),
        relativePath: p.posix.join('attachments', name),
        sha256: digest,
      );
      final updated = dossier.copyWith(
        entries: [...dossier.entries, entry],
        updatedAt: DateTime.now().toUtc(),
      );
      await save(updated);
      return updated;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  /// Returns null for a missing or unsafe path. This must be used before opening.
  Future<String?> resolvedPath(DossierEntry entry) async {
    if (!_validRelativePath(entry.relativePath)) return null;
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
    if (!_validRelativePath(entry.relativePath)) {
      return const DossierIntegrityResult(DossierIntegrityStatus.unsafe);
    }
    final candidate = p.normalize(
      p.join(directory.absolute.path, p.fromUri(entry.relativePath)),
    );
    if (!p.isWithin(directory.absolute.path, candidate)) {
      return const DossierIntegrityResult(DossierIntegrityStatus.unsafe);
    }
    if (!await File(candidate).exists()) {
      return const DossierIntegrityResult(DossierIntegrityStatus.missing);
    }
    final path = await resolvedPath(entry);
    if (path == null) {
      return const DossierIntegrityResult(DossierIntegrityStatus.unsafe);
    }
    try {
      final actual = await _hash(File(path));
      return DossierIntegrityResult(
        actual == entry.sha256
            ? DossierIntegrityStatus.matches
            : DossierIntegrityStatus.changed,
        actualSha256: actual,
      );
    } on FileSystemException {
      return const DossierIntegrityResult(DossierIntegrityStatus.unreadable);
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
    entries[index] = entry.copyWith(sha256: result.actualSha256);
    final updated = dossier.copyWith(
      entries: entries,
      updatedAt: DateTime.now().toUtc(),
    );
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
      final link = Uri(
        pathSegments: p.posix.split(entry.relativePath),
      ).toString();
      buffer
        ..writeln('${index + 1}. [${_markdownText(entry.title)}]($link)')
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
