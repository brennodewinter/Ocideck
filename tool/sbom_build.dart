// Builds the OciDeck component inventory and serialises it to the two common
// machine-readable SBOM formats: CycloneDX 1.6 JSON and SPDX 2.3 JSON.
//
// The inventory is *derived*, never hand-maintained. Every fact already lives
// in a file that is the source of truth for it:
//
//   * pubspec.lock                    — resolved Dart/Flutter packages: version,
//                                       archive sha256, hosted URL, and whether
//                                       the dep is direct/dev/transitive.
//   * .dart_tool/package_config.json  — each package's on-disk root, used to
//                                       classify its licence (shared with the
//                                       licence gate; see license_detect.dart).
//   * assets/web_export/MANIFEST.json — vendored JS/CSS bundles inlined into the
//                                       HTML export: npm name, version, sha256,
//                                       source, licence.
//   * pubspec.yaml                    — app version, vendored path forks, and
//                                       the bundled fonts.
//   * .tool-versions                  — the pinned Flutter SDK version.
//
// Determinism: the component list is stably sorted and the document identifier
// (serialNumber / documentNamespace) is derived from a hash of the timestamp-
// free content. The only wall-clock value is the creation timestamp, which the
// `--check` staleness gate strips before comparing (see stripVolatile*).

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';

import 'license_detect.dart';

const manifestPath = 'assets/web_export/MANIFEST.json';
const cdxOutputPath = 'sbom/ocideck.cdx.json';
const spdxOutputPath = 'sbom/ocideck.spdx.json';
const mdOutputPath = 'sbom/ocideck.sbom.md';

/// Human-readable labels for the component groups, in display order.
const _groupLabels = <String, String>{
  'application': 'Application',
  'dart-package': 'Dart / Flutter packages',
  'vendored-fork': 'Vendored plugin forks (third_party/)',
  'npm-bundle': 'Vendored JavaScript bundles (HTML export)',
  'export-asset': 'Vendored export assets',
  'font': 'Bundled fonts',
  'sdk': 'Build SDKs',
};

/// SPDX licence identifiers we may emit as a structured `id`. Anything else is
/// emitted as a free-text `name` (or `NOASSERTION`) so the document stays valid.
const _validSpdxIds = <String>{
  'MIT',
  'BSD-2-Clause',
  'BSD-3-Clause',
  'Apache-2.0',
  'MPL-2.0',
  'ISC',
  'Zlib',
  'BSL-1.0',
  'Unlicense',
  'OFL-1.1',
  'CC0-1.0',
  'EUPL-1.2',
};

/// Upstream origins of the two vendored (forked) plugins in `third_party/`.
/// Kept here (and in THIRD_PARTY_NOTICES.md) because a path dependency carries
/// no upstream URL, no upstream revision and no archive hash of its own.
///
/// [revision] is the upstream commit the fork was branched from, verified by
/// hashing every file in the package subtree at that commit and comparing it
/// with the vendored copy: every file matches except the ones listed in the
/// fork's own `MODIFICATIONS.md`. [subdir] is the package's path inside the
/// upstream monorepo, so `$vcs/tree/$revision/$subdir` resolves to the exact
/// source this fork descends from.
///
/// The **licence is deliberately absent here**. It is classified from the
/// fork's own LICENSE file by [licenseForPackage] — the same classifier the
/// `make licenses` gate uses — because hardcoding it is precisely how
/// `desktop_multi_window` came to be listed as MIT in every SBOM while the
/// file on disk was the Apache-2.0 text (© 2021 Mixin). The MIT that GitHub's
/// API reports for `MixinNetwork/flutter-plugins` is the *root* LICENSE of the
/// monorepo; the package directory carries its own, and that one governs.
const _forkOrigins = <String, ({String vcs, String revision, String subdir})>{
  'desktop_multi_window': (
    vcs: 'https://github.com/MixinNetwork/flutter-plugins',
    revision: '58a5868d1cb9031defa5db5868d6aaea0486d24a',
    subdir: 'packages/desktop_multi_window',
  ),
  'screen_retriever_macos': (
    vcs: 'https://github.com/leanflutter/screen_retriever',
    revision: 'ed1e52204d75b69330fb4b0e0b8d4d57e3c53833',
    subdir: 'packages/screen_retriever_macos',
  ),
};

/// SHA-256 over a vendored fork's entire directory tree.
///
/// A path dependency has no pub archive, so there is no upstream hash to
/// record — but "no hash at all" leaves the two forks as the only components a
/// verifier cannot check. This fills that gap with a hash of what we actually
/// ship: the digest of a sorted `<relative path> <sha256>` line per file. It is
/// recomputed on every `make sbom-verify`, so a tampered or accidentally-edited
/// fork shows up as a stale SBOM rather than passing unnoticed.
///
/// Dot-directories and dot-files are skipped: they are build/editor droppings
/// (`.DS_Store`, `.dart_tool`) that are not part of the vendored source and
/// would make the hash machine-dependent.
String forkTreeHash(Directory dir) {
  final prefix = '${dir.path}${Platform.pathSeparator}';
  final lines = <String>[];
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final rel = entity.path.substring(prefix.length).replaceAll(r'\', '/');
    if (rel.split('/').any((seg) => seg.startsWith('.'))) continue;
    lines.add('$rel ${sha256.convert(entity.readAsBytesSync())}');
  }
  lines.sort();
  return sha256.convert(utf8.encode('${lines.join('\n')}\n')).toString();
}

/// One entry in the bill of materials.
class SbomComponent {
  SbomComponent({
    required this.ref,
    required this.group,
    required this.type,
    required this.name,
    required this.license,
    this.version,
    this.purl,
    this.sha256,
    this.downloadUrl,
    this.vcsUrl,
    this.upstreamRevision,
    this.scope,
    this.note,
  });

  /// Stable, unique identifier used as the CycloneDX `bom-ref`.
  final String ref;

  /// Origin bucket: dart-package, vendored-fork, npm-bundle, export-asset,
  /// font, or sdk. Surfaced as a property for filtering.
  final String group;

  /// CycloneDX/SPDX component type: library, framework, file, application.
  final String type;
  final String name;
  final String? version;
  final String? purl;
  final String? sha256;
  final String? downloadUrl;
  final String? vcsUrl;

  /// Upstream commit a vendored fork descends from, or null for anything that
  /// has a version-pinned archive instead.
  final String? upstreamRevision;

  /// Classified licence family or SPDX expression (e.g. `Apache-2.0 OR MPL-2.0`).
  final String license;

  /// pubspec dependency scope: "direct main" / "direct dev" / "transitive" /
  /// "direct overridden", or null for non-package components.
  final String? scope;
  final String? note;

  bool get isDirect => scope != null && scope!.startsWith('direct');
}

/// The full inventory: the root application component plus everything it ships.
class Inventory {
  Inventory(this.root, this.components);
  final SbomComponent root;
  final List<SbomComponent> components;

  List<SbomComponent> get all => [root, ...components];
  List<SbomComponent> get directDeps =>
      components.where((c) => c.isDirect).toList();
}

// ---------------------------------------------------------------------------
// Inventory assembly
// ---------------------------------------------------------------------------

/// Read every source and return the sorted inventory. Runs from the repo root.
Inventory buildInventory() {
  final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
  final appVersion = pubspec['version'].toString();

  final root = SbomComponent(
    ref: 'ocideck@$appVersion',
    group: 'application',
    type: 'application',
    name: 'ocideck',
    version: appVersion,
    license: 'EUPL-1.2',
    purl: 'pkg:generic/ocideck@$appVersion',
    note: pubspec['description']?.toString(),
  );

  final components = <SbomComponent>[
    ..._dartPackages(),
    ..._npmBundles(),
    ..._fonts(pubspec),
    ..._sdks(pubspec),
  ];

  components.sort((a, b) {
    final byGroup = a.group.compareTo(b.group);
    if (byGroup != 0) return byGroup;
    final byName = a.name.compareTo(b.name);
    if (byName != 0) return byName;
    return a.ref.compareTo(b.ref);
  });

  return Inventory(root, components);
}

/// Map of package name -> resolved on-disk root, from package_config.json,
/// used only to locate each package's LICENSE file for classification.
Map<String, Directory> _packageRoots() {
  final cfgFile = File('.dart_tool/package_config.json');
  if (!cfgFile.existsSync()) {
    throw StateError(
      'No .dart_tool/package_config.json — run "flutter pub get" first.',
    );
  }
  final base = cfgFile.absolute.parent.uri;
  final cfg = jsonDecode(cfgFile.readAsStringSync()) as Map<String, dynamic>;
  final roots = <String, Directory>{};
  for (final pkg in (cfg['packages'] as List)) {
    final name = pkg['name'] as String;
    final rootUri = pkg['rootUri'] as String;
    final resolved = rootUri.startsWith('file:')
        ? Uri.parse(rootUri.endsWith('/') ? rootUri : '$rootUri/')
        : base.resolve(rootUri.endsWith('/') ? rootUri : '$rootUri/');
    roots[name] = Directory.fromUri(resolved);
  }
  return roots;
}

/// All resolved Dart/Flutter packages from pubspec.lock (direct + transitive).
List<SbomComponent> _dartPackages() {
  final lock = loadYaml(File('pubspec.lock').readAsStringSync()) as YamlMap;
  final packages = lock['packages'] as YamlMap;
  final roots = _packageRoots();
  final out = <SbomComponent>[];

  for (final entry in packages.entries) {
    final name = entry.key.toString();
    final data = entry.value as YamlMap;
    final version = data['version'].toString();
    final source = data['source'].toString();
    final scope = data['dependency'].toString();
    final desc = data['description'];

    final root = roots[name];
    final license = root != null
        ? licenseForPackage(name, root)
        : 'NOASSERTION';

    if (source == 'hosted') {
      final descMap = desc as YamlMap;
      final host = descMap['url'].toString();
      out.add(
        SbomComponent(
          ref: 'pkg:pub/$name@$version',
          group: 'dart-package',
          type: 'library',
          name: name,
          version: version,
          purl: 'pkg:pub/$name@$version',
          sha256: descMap['sha256']?.toString(),
          downloadUrl: '$host/packages/$name/versions/$version',
          license: license,
          scope: scope,
        ),
      );
    } else if (source == 'path') {
      final fork = _forkOrigins[name];
      final dir = Directory('third_party/$name');
      out.add(
        SbomComponent(
          ref: 'fork:$name@$version',
          group: 'vendored-fork',
          type: 'library',
          name: name,
          version: version,
          license: license,
          sha256: dir.existsSync() ? forkTreeHash(dir) : null,
          vcsUrl: fork == null
              ? null
              : '${fork.vcs}/tree/${fork.revision}/${fork.subdir}',
          upstreamRevision: fork?.revision,
          scope: scope,
          note:
              'Vendored fork in third_party/$name; the local changes are '
              'recorded in third_party/$name/MODIFICATIONS.md. The SHA-256 is '
              'a tree hash of the vendored directory, not an upstream archive '
              'hash — a path dependency has none.',
        ),
      );
    } else {
      // sdk / git — carry name+version+licence; no archive hash to pin.
      out.add(
        SbomComponent(
          ref: '$source:$name@$version',
          group: 'dart-package',
          type: 'library',
          name: name,
          version: version,
          license: license,
          scope: scope,
          note: 'Source: $source.',
        ),
      );
    }
  }
  return out;
}

/// Vendored JS/CSS bundles inlined into the offline HTML export.
List<SbomComponent> _npmBundles() {
  final manifest =
      jsonDecode(File(manifestPath).readAsStringSync()) as Map<String, dynamic>;
  final bundles = (manifest['bundles'] as List).cast<Map<String, dynamic>>();
  final out = <SbomComponent>[];

  for (final b in bundles) {
    final file = b['file'] as String;
    final npm = b['npm'] as String?;
    final version = b['version'] as String?;
    final license = (b['license'] as String?) ?? 'NOASSERTION';
    final source = b['source'] as String?;
    final sha = (b['sha256'] as String?)?.toLowerCase();

    if (npm != null && version != null) {
      out.add(
        SbomComponent(
          ref: 'pkg:npm/$npm@$version',
          group: 'npm-bundle',
          type: 'library',
          name: npm,
          version: version,
          purl: 'pkg:npm/$npm@$version',
          sha256: sha,
          downloadUrl: source,
          license: license,
          note: 'Vendored into $file, inlined into the HTML export.',
        ),
      );
    } else {
      // Integrity-only asset (e.g. the highlight.js theme CSS) — no npm package.
      out.add(
        SbomComponent(
          ref: 'export-asset:$file',
          group: 'export-asset',
          type: 'file',
          name: file,
          version: version,
          sha256: sha,
          downloadUrl: source,
          license: license,
          note: 'Hash-pinned export asset (no npm package).',
        ),
      );
    }
  }
  return out;
}

/// Bundled fonts declared in pubspec.yaml (one component per font file so each
/// stays individually hash-verifiable, mirroring the JS manifest).
List<SbomComponent> _fonts(YamlMap pubspec) {
  final flutter = pubspec['flutter'] as YamlMap?;
  final fonts = flutter?['fonts'] as YamlList?;
  if (fonts == null) return const [];

  final out = <SbomComponent>[];
  for (final family in fonts) {
    final familyName = family['family'].toString();
    final assets = (family['fonts'] as YamlList?) ?? const [];
    for (final f in assets) {
      final asset = f['asset'].toString();
      final file = File(asset);
      final sha = file.existsSync()
          ? sha256.convert(file.readAsBytesSync()).toString()
          : null;
      final base = asset.split('/').last;
      out.add(
        SbomComponent(
          ref: 'font:$asset',
          group: 'font',
          type: 'file',
          name: familyName,
          purl: 'pkg:generic/${Uri.encodeComponent(familyName)}',
          sha256: sha,
          license: 'OFL-1.1',
          note: 'Bundled font file assets/$base.',
        ),
      );
    }
  }
  return out;
}

/// The pinned build SDKs — the runtime foundation the product ships on.
List<SbomComponent> _sdks(YamlMap pubspec) {
  final out = <SbomComponent>[];

  final toolVersions = File('.tool-versions');
  if (toolVersions.existsSync()) {
    for (final line in toolVersions.readAsLinesSync()) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2 && parts[0] == 'flutter') {
        final version = parts[1].replaceAll('-stable', '');
        out.add(
          SbomComponent(
            ref: 'sdk:flutter@$version',
            group: 'sdk',
            type: 'framework',
            name: 'flutter',
            version: version,
            license: 'BSD-3-Clause',
            downloadUrl: 'https://flutter.dev',
            vcsUrl: 'https://github.com/flutter/flutter',
            note: 'Pinned build SDK (.tool-versions).',
          ),
        );
      }
    }
  }

  final sdkConstraint = (pubspec['environment'] as YamlMap?)?['sdk']
      ?.toString();
  if (sdkConstraint != null) {
    out.add(
      SbomComponent(
        ref: 'sdk:dart@$sdkConstraint',
        group: 'sdk',
        type: 'framework',
        name: 'dart',
        version: sdkConstraint,
        license: 'BSD-3-Clause',
        downloadUrl: 'https://dart.dev',
        vcsUrl: 'https://github.com/dart-lang/sdk',
        note: 'Dart SDK constraint from pubspec.yaml (environment.sdk).',
      ),
    );
  }
  return out;
}

// ---------------------------------------------------------------------------
// Serialisation
// ---------------------------------------------------------------------------

/// Deterministic urn:uuid derived from the timestamp-free content hash, so the
/// document identity is stable across regenerations of the same inventory.
String _deterministicUuid(String content) {
  final h = sha256.convert(utf8.encode(content)).toString();
  return 'urn:uuid:${h.substring(0, 8)}-${h.substring(8, 12)}-5'
      '${h.substring(13, 16)}-8${h.substring(17, 20)}-${h.substring(20, 32)}';
}

const _jsonEncoder = JsonEncoder.withIndent('  ');

/// CycloneDX licence node for a classified [kind]: an `expression` for SPDX
/// expressions, a structured `id` for known SPDX ids, else a free-text `name`.
Map<String, dynamic> _cdxLicense(String kind) {
  if (kind.contains(' OR ') || kind.contains(' AND ')) {
    return {'expression': kind};
  }
  final fam = licenseFamily(kind);
  if (_validSpdxIds.contains(fam)) {
    return {
      'license': {'id': fam},
    };
  }
  return {
    'license': {'name': kind},
  };
}

List<Map<String, dynamic>> _cdxExternalRefs(SbomComponent c) {
  final refs = <Map<String, dynamic>>[];
  if (c.downloadUrl != null) {
    refs.add({'type': 'distribution', 'url': c.downloadUrl});
  }
  if (c.vcsUrl != null) refs.add({'type': 'vcs', 'url': c.vcsUrl});
  return refs;
}

Map<String, dynamic> _cdxComponent(SbomComponent c) {
  final m = <String, dynamic>{
    'bom-ref': c.ref,
    'type': c.type,
    'name': c.name,
    if (c.version != null) 'version': c.version,
    if (c.purl != null) 'purl': c.purl,
    'licenses': [_cdxLicense(c.license)],
    if (c.sha256 != null)
      'hashes': [
        {'alg': 'SHA-256', 'content': c.sha256},
      ],
  };
  final ext = _cdxExternalRefs(c);
  if (ext.isNotEmpty) m['externalReferences'] = ext;
  final props = <Map<String, String>>[
    {'name': 'ocideck:group', 'value': c.group},
    if (c.scope != null) {'name': 'cdx:pub:scope', 'value': c.scope!},
    if (c.upstreamRevision != null)
      {'name': 'ocideck:upstream-revision', 'value': c.upstreamRevision!},
    if (c.note != null) {'name': 'ocideck:note', 'value': c.note!},
  ];
  m['properties'] = props;
  return m;
}

/// Serialise the inventory to CycloneDX 1.6 JSON. [timestamp] is the only
/// non-deterministic value.
String toCycloneDx(Inventory inv, String timestamp) {
  final components = inv.components.map(_cdxComponent).toList();
  final core = jsonEncode(components); // timestamp-free identity basis
  final serial = _deterministicUuid('cdx$core');

  final bom = <String, dynamic>{
    r'$schema': 'http://cyclonedx.org/schema/bom-1.6.schema.json',
    'bomFormat': 'CycloneDX',
    'specVersion': '1.6',
    'serialNumber': serial,
    'version': 1,
    'metadata': {
      'timestamp': timestamp,
      'tools': {
        'components': [
          {
            'type': 'application',
            'group': 'ocideck',
            'name': 'generate_sbom.dart',
            'version': '1.0',
          },
        ],
      },
      'component': _cdxComponent(inv.root),
      'properties': _craProperties(),
    },
    'components': components,
    'dependencies': [
      {
        'ref': inv.root.ref,
        'dependsOn': inv.directDeps.map((c) => c.ref).toList(),
      },
    ],
  };
  return _jsonEncoder.convert(bom);
}

List<Map<String, String>> _craProperties() => [
  {'name': 'cra:regulation', 'value': 'EU 2024/2847 (Cyber Resilience Act)'},
  {
    'name': 'cra:reference',
    'value': 'Annex I, Part II, §1 — software bill of materials',
  },
  {'name': 'ocideck:generated-by', 'value': 'tool/generate_sbom.dart'},
];

// -- SPDX -------------------------------------------------------------------

String _spdxId(int index, String name) {
  final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9.-]'), '-');
  return 'SPDXRef-$index-$safe';
}

/// SPDX `licenseConcluded`/`licenseDeclared` value: an SPDX expression as-is, a
/// known id as-is, else `NOASSERTION`.
String _spdxLicense(String kind) {
  if (kind.contains(' OR ') || kind.contains(' AND ')) return kind;
  final fam = licenseFamily(kind);
  return _validSpdxIds.contains(fam) ? fam : 'NOASSERTION';
}

Map<String, dynamic> _spdxPackage(SbomComponent c, String spdxId) {
  final lic = _spdxLicense(c.license);
  final pkg = <String, dynamic>{
    'SPDXID': spdxId,
    'name': c.name,
    if (c.version != null) 'versionInfo': c.version,
    'downloadLocation': c.downloadUrl ?? c.vcsUrl ?? 'NOASSERTION',
    'filesAnalyzed': false,
    'licenseConcluded': lic,
    'licenseDeclared': lic,
  };
  if (c.sha256 != null) {
    pkg['checksums'] = [
      {'algorithm': 'SHA256', 'checksumValue': c.sha256},
    ];
  }
  if (c.purl != null) {
    pkg['externalRefs'] = [
      {
        'referenceCategory': 'PACKAGE-MANAGER',
        'referenceType': 'purl',
        'referenceLocator': c.purl,
      },
    ];
  }
  if (c.upstreamRevision != null) {
    pkg['sourceInfo'] =
        'Vendored from ${c.vcsUrl} at commit '
        '${c.upstreamRevision}.';
  }
  if (c.note != null) pkg['comment'] = c.note;
  return pkg;
}

/// Serialise the inventory to SPDX 2.3 JSON. [timestamp] is the only
/// non-deterministic value.
String toSpdx(Inventory inv, String timestamp) {
  final all = inv.all;
  final ids = <String, String>{};
  for (var i = 0; i < all.length; i++) {
    ids[all[i].ref] = _spdxId(i, all[i].name);
  }
  final rootId = ids[inv.root.ref]!;

  final packages = all.map((c) => _spdxPackage(c, ids[c.ref]!)).toList();
  final core = jsonEncode(packages);
  final serial = _deterministicUuid('spdx$core').replaceFirst('urn:uuid:', '');

  final relationships = <Map<String, dynamic>>[
    {
      'spdxElementId': 'SPDXRef-DOCUMENT',
      'relationshipType': 'DESCRIBES',
      'relatedSpdxElement': rootId,
    },
    for (final c in inv.directDeps)
      {
        'spdxElementId': rootId,
        'relationshipType': 'DEPENDS_ON',
        'relatedSpdxElement': ids[c.ref]!,
      },
  ];

  final doc = <String, dynamic>{
    'spdxVersion': 'SPDX-2.3',
    'dataLicense': 'CC0-1.0',
    'SPDXID': 'SPDXRef-DOCUMENT',
    'name': 'ocideck-${inv.root.version}',
    'documentNamespace': 'https://ocideck.app/spdx/$serial',
    'creationInfo': {
      'created': timestamp,
      'creators': ['Tool: ocideck-generate_sbom-1.0'],
      'comment':
          'Generated by tool/generate_sbom.dart for EU 2024/2847 (Cyber '
          'Resilience Act), Annex I, Part II, §1.',
    },
    'packages': packages,
    'relationships': relationships,
  };
  return _jsonEncoder.convert(doc);
}

// -- Markdown (human-readable) ----------------------------------------------

/// A short, scan-friendly source hint for the last table column.
String _sourceHint(SbomComponent c) {
  if (c.purl != null) return '`${c.purl}`';
  if (c.vcsUrl != null) return c.vcsUrl!;
  if (c.note != null) return c.note!;
  return '—';
}

void _markdownGroup(StringBuffer b, String group, List<SbomComponent> items) {
  if (items.isEmpty) return;
  final label = _groupLabels[group] ?? group;
  b.writeln('### $label (${items.length})\n');
  b.writeln('| Component | Version | Licence | Source |');
  b.writeln('| --- | --- | --- | --- |');
  for (final c in items) {
    final scope = c.scope != null ? ' _(${c.scope})_' : '';
    b.writeln(
      '| ${c.name}$scope | ${c.version ?? '—'} | ${c.license} '
      '| ${_sourceHint(c)} |',
    );
  }
  b.writeln();
}

/// Render the inventory as a human-readable Markdown document. Fully
/// deterministic (no timestamp), so it needs no volatile-field normalisation in
/// the staleness check. Full SHA-256 hashes and purls live in the JSON SBOMs;
/// this view is for scanning names, versions and licences by eye.
String toMarkdown(Inventory inv) {
  final b = StringBuffer();
  b.writeln('# OciDeck — Software Bill of Materials\n');
  b.writeln(
    '> **Generated file — do not edit by hand.** Produced by '
    '`dart run tool/generate_sbom.dart` (`make sbom`) from pubspec.lock, '
    'assets/web_export/MANIFEST.json, pubspec.yaml and .tool-versions. '
    'The machine-readable equivalents are '
    '[`ocideck.cdx.json`](ocideck.cdx.json) (CycloneDX 1.6) and '
    '[`ocideck.spdx.json`](ocideck.spdx.json) (SPDX 2.3); those carry the '
    'SHA-256 hashes and purls. See [`../docs/SBOM.md`](../docs/SBOM.md).\n',
  );
  b.writeln(
    'This is **${inv.root.name} ${inv.root.version}** (licence '
    '${inv.root.license}) and every third-party component it ships '
    '(${inv.components.length} in total), direct and transitive — the '
    'inventory the EU Cyber Resilience Act (Reg. (EU) 2024/2847, Annex I '
    'Part II §1) requires.\n',
  );

  // Licence summary.
  final byLicense = <String, int>{};
  for (final c in inv.components) {
    final fam = licenseFamily(c.license);
    byLicense[fam] = (byLicense[fam] ?? 0) + 1;
  }
  final licKeys = byLicense.keys.toList()
    ..sort((a, b) => byLicense[b]!.compareTo(byLicense[a]!));
  b.writeln('## Licences\n');
  b.writeln('| Licence | Components |');
  b.writeln('| --- | ---: |');
  for (final k in licKeys) {
    b.writeln('| $k | ${byLicense[k]} |');
  }
  b.writeln();

  // Components grouped in a stable, human-sensible order.
  b.writeln('## Components\n');
  for (final group in _groupLabels.keys) {
    if (group == 'application') continue; // the root is described above
    _markdownGroup(
      b,
      group,
      inv.components.where((c) => c.group == group).toList(),
    );
  }
  return b.toString().trimRight();
}

// ---------------------------------------------------------------------------
// Staleness comparison
// ---------------------------------------------------------------------------

/// Re-encode [json] with the volatile CycloneDX fields removed, so a pure
/// regeneration (no dependency change) compares equal to the committed file.
String stripVolatileCdx(String json) {
  final m = jsonDecode(json) as Map<String, dynamic>;
  m.remove('serialNumber');
  (m['metadata'] as Map?)?.remove('timestamp');
  return _jsonEncoder.convert(m);
}

/// SPDX counterpart of [stripVolatileCdx].
String stripVolatileSpdx(String json) {
  final m = jsonDecode(json) as Map<String, dynamic>;
  m.remove('documentNamespace');
  (m['creationInfo'] as Map?)?.remove('created');
  return _jsonEncoder.convert(m);
}
