// Content-addressed "module data pack" codec (PENTEST_MIAUW.md §6).
//
// The Informatieveiligheid module ships NO reference data in the base app
// payload. Enabling it fetches a single versioned pack — a zip of pre-normalised
// JSON plus an inner MANIFEST.json — verifies it, and caches it locally so the
// module then runs offline. This file is the pure-Dart codec for that pack:
//
//   * [buildSecPack]  — deterministically assembles data files + an inner
//     MANIFEST.json (per-file sha256 + upstream version + licence + source),
//     mirroring assets/web_export/MANIFEST.json. Used by the build-time tooling
//     (tool/build_secmodule_pack.dart) to cut a pack and print its outer sha256.
//   * [openAndVerifySecPack] — decodes a pack and checks every file against the
//     inner manifest (a zip-bomb-capped, tamper-evident unpack). The OUTER hash
//     (against the value compiled into the app) is verified separately by the
//     provisioner; this is the SECOND integrity layer, inside the pack.
//
// Deliberately free of dart:io / Flutter so it compiles on web and can be
// reused verbatim by the command-line packing tool.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

/// The inner manifest's file name inside a pack.
const secPackManifestName = 'MANIFEST.json';

/// Schema version of the inner manifest, so a future format change is
/// detectable rather than silently mis-parsed.
const secPackManifestVersion = 1;

/// Fixed DOS-epoch modification time baked into every pack entry so the same
/// inputs always produce byte-identical pack bytes (and therefore a stable
/// outer sha256 to pin). 2024-01-01T00:00:00Z — comfortably after the 1980 DOS
/// epoch floor.
final _fixedModified = DateTime.utc(2024, 1, 1);
const _fixedModTimeSecs = 1704067200; // 2024-01-01T00:00:00Z

/// Lowercase hex sha256 of [bytes].
String secPackSha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// A normalised dataset file to include in a pack (build side).
class SecPackDataFile {
  /// POSIX-relative name inside the pack (no leading slash, no `..`).
  final String name;
  final Uint8List bytes;

  /// Upstream dataset version this file was cut from (e.g. `CWE 4.20`).
  final String upstreamVersion;

  /// SPDX-ish licence of the upstream data (e.g. `MITRE Terms of Use`).
  final String licence;

  /// Canonical upstream source URL, preserved for the compliance appendix.
  final String source;

  const SecPackDataFile({
    required this.name,
    required this.bytes,
    required this.upstreamVersion,
    required this.licence,
    required this.source,
  });
}

/// A per-file record inside the inner MANIFEST.json.
class SecPackFileEntry {
  final String name;
  final String sha256;
  final String version;
  final String licence;
  final String source;

  const SecPackFileEntry({
    required this.name,
    required this.sha256,
    required this.version,
    required this.licence,
    required this.source,
  });

  Map<String, Object?> toJson() => {
    'file': name,
    'sha256': sha256,
    'version': version,
    'licence': licence,
    'source': source,
  };

  factory SecPackFileEntry.fromJson(Map<String, Object?> json) {
    return SecPackFileEntry(
      name: json['file'] as String,
      sha256: (json['sha256'] as String).toLowerCase(),
      version: json['version'] as String? ?? '',
      licence: json['licence'] as String? ?? '',
      source: json['source'] as String? ?? '',
    );
  }
}

/// The inner MANIFEST.json of a pack.
class SecPackManifest {
  final int manifestVersion;
  final String packVersion;
  final List<SecPackFileEntry> files;

  const SecPackManifest({
    required this.manifestVersion,
    required this.packVersion,
    required this.files,
  });

  Map<String, Object?> toJson() => {
    'manifestVersion': manifestVersion,
    'packVersion': packVersion,
    'files': [for (final f in files) f.toJson()],
  };

  factory SecPackManifest.fromJson(Map<String, Object?> json) {
    final rawFiles = (json['files'] as List?) ?? const [];
    return SecPackManifest(
      manifestVersion: (json['manifestVersion'] as num?)?.toInt() ?? 0,
      packVersion: json['packVersion'] as String? ?? '',
      files: [
        for (final f in rawFiles)
          SecPackFileEntry.fromJson(Map<String, Object?>.from(f as Map)),
      ],
    );
  }
}

/// The verified contents of a pack: its manifest plus the data files (the inner
/// MANIFEST.json itself is excluded from [files]).
class SecPackContents {
  final SecPackManifest manifest;
  final Map<String, Uint8List> files;

  const SecPackContents({required this.manifest, required this.files});
}

/// Raised when a pack is malformed, fails its inner integrity check, or exceeds
/// the decompression cap. The provisioner turns this into a rejection with
/// nothing cached.
class SecPackFormatException implements Exception {
  final String message;
  const SecPackFormatException(this.message);
  @override
  String toString() => 'SecPackFormatException: $message';
}

/// Assemble [files] plus an inner MANIFEST.json into deterministic pack bytes.
/// Entries are STORE-compressed and sorted by name with a fixed timestamp, so
/// identical inputs always yield the same bytes and therefore the same outer
/// sha256 to pin into the app.
Uint8List buildSecPack({
  required String packVersion,
  required List<SecPackDataFile> files,
}) {
  final sorted = [...files]..sort((a, b) => a.name.compareTo(b.name));
  final entries = [
    for (final f in sorted)
      SecPackFileEntry(
        name: f.name,
        sha256: secPackSha256Hex(f.bytes),
        version: f.upstreamVersion,
        licence: f.licence,
        source: f.source,
      ),
  ];
  final manifest = SecPackManifest(
    manifestVersion: secPackManifestVersion,
    packVersion: packVersion,
    files: entries,
  );
  final manifestBytes = utf8.encode(
    const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
  );

  final archive = Archive();
  _addStored(archive, secPackManifestName, manifestBytes);
  for (final f in sorted) {
    _addStored(archive, f.name, f.bytes);
  }
  return ZipEncoder().encodeBytes(archive, modified: _fixedModified);
}

void _addStored(Archive archive, String name, List<int> bytes) {
  final entry = ArchiveFile(name, bytes.length, bytes)
    ..compression = CompressionType.none
    ..lastModTime = _fixedModTimeSecs;
  archive.add(entry);
}

/// Decode [zipBytes] and verify every data file against the inner
/// MANIFEST.json. Throws [SecPackFormatException] on a corrupt archive, a
/// missing/duplicate/unexpected file, a per-file sha256 mismatch, or a total
/// decompressed size over [maxBytes] (zip-bomb guard). Returns the verified
/// contents on success.
SecPackContents openAndVerifySecPack(
  List<int> zipBytes, {
  int maxBytes = 32 * 1024 * 1024,
}) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(zipBytes);
  } catch (e) {
    throw SecPackFormatException('kon het pakket niet uitpakken: $e');
  }

  final data = <String, Uint8List>{};
  Uint8List? manifestBytes;
  var total = 0;
  for (final f in archive.files) {
    if (!f.isFile) continue;
    final content = f.content;
    total += content.length;
    if (total > maxBytes) {
      throw const SecPackFormatException(
        'pakket overschrijdt de groottelimiet',
      );
    }
    if (f.name == secPackManifestName) {
      manifestBytes = Uint8List.fromList(content);
      continue;
    }
    if (data.containsKey(f.name)) {
      throw SecPackFormatException('dubbel lid in pakket: ${f.name}');
    }
    data[f.name] = Uint8List.fromList(content);
  }

  if (manifestBytes == null) {
    throw const SecPackFormatException('pakket mist $secPackManifestName');
  }
  final SecPackManifest manifest;
  try {
    manifest = SecPackManifest.fromJson(
      Map<String, Object?>.from(jsonDecode(utf8.decode(manifestBytes)) as Map),
    );
  } catch (e) {
    throw SecPackFormatException('ongeldige $secPackManifestName: $e');
  }
  if (manifest.manifestVersion != secPackManifestVersion) {
    throw SecPackFormatException(
      'onbekende manifestversie ${manifest.manifestVersion}',
    );
  }

  _verifyEntries(manifest, data);
  return SecPackContents(manifest: manifest, files: data);
}

/// Every manifest entry must be present with a matching sha256, and every
/// packaged file must be listed in the manifest (no smuggled extras).
void _verifyEntries(SecPackManifest manifest, Map<String, Uint8List> data) {
  final listed = <String>{};
  for (final entry in manifest.files) {
    final bytes = data[entry.name];
    if (bytes == null) {
      throw SecPackFormatException(
        'manifest verwijst naar ${entry.name}, '
        'maar dat lid ontbreekt',
      );
    }
    final actual = secPackSha256Hex(bytes);
    if (actual != entry.sha256) {
      throw SecPackFormatException(
        'sha256 van ${entry.name} wijkt af van '
        'het manifest',
      );
    }
    listed.add(entry.name);
  }
  for (final name in data.keys) {
    if (!listed.contains(name)) {
      throw SecPackFormatException('onverwacht lid buiten manifest: $name');
    }
  }
}
