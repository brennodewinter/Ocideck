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

/// Upstream origins of the vendored (forked) packages in `third_party/`.
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
  'markdown_quill': (
    vcs: 'https://github.com/TarekkMA/markdown_quill',
    revision: '49641654bd584c6f0fc398c2c91383cf13a3424b',
    subdir: '',
  ),
};

/// SHA-256 over a vendored fork's entire directory tree.
///
/// A path dependency has no pub archive, so there is no upstream hash to
/// record — but "no hash at all" leaves the forks as the only components a
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

/// Hosts that distribute someone else's package rather than supplying it. A
/// registry or a CDN is the delivery channel, not the supplier, so a URL
/// pointing at one yields no supplier at all instead of a wrong one.
const _nonSupplierHosts = <String>{
  'pub.dev',
  'pub.dartlang.org',
  'cdn.jsdelivr.net',
  'cdnjs.cloudflare.com',
  'unpkg.com',
  'npmjs.com',
  'registry.npmjs.org',
};

/// Where each SDK that pub resolves packages *from* is published.
///
/// A `source: sdk` entry in pubspec.lock says the package is shipped inside
/// that SDK, and that is the one thing the lock file states about its origin:
/// `flutter_test`, `flutter_localizations` and `sky_engine` declare no
/// repository of their own. So the SDK's publisher is their supplier, and this
/// map is also what the SDK components themselves are built from — one
/// statement, not two that can drift.
const _sdkVcsUrls = <String, String>{
  'flutter': 'https://github.com/flutter/flutter',
  'dart': 'https://github.com/dart-lang/sdk',
};

/// Forges where the first path segment is the account a project is published
/// under — the closest thing to a supplier name that a package declares about
/// itself without asking the network.
const _forgeHosts = <String>{
  'github.com',
  'gitlab.com',
  'bitbucket.org',
  'codeberg.org',
  'sr.ht',
};

/// The supplier a declared source URL names, or null when it names none.
///
/// This is the whole of the NTIA "supplier name" derivation, and it is
/// deliberately thin: `https://github.com/dart-lang/tools` yields `dart-lang`,
/// `https://flutter.dev` yields `flutter.dev`, and a registry or CDN URL yields
/// nothing. There is no lookup table of "who really maintains what" — such a
/// table is a guess that ages badly and reads as a fact once it is in an SBOM.
///
/// The account is emitted as an SPDX `Organization:`. Whether a forge account
/// belongs to a company or to one person is not determinable offline, and
/// picking the account namespace is the conventional choice; the [url] travels
/// with the name so a reader can check who it is.
({String name, String url})? supplierFromUrl(String? url) {
  if (url == null || url.trim().isEmpty) return null;
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  if (_nonSupplierHosts.contains(host)) return null;
  if (_forgeHosts.contains(host)) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    return (
      name: segments.first,
      url: '${uri.scheme}://$host/${segments.first}',
    );
  }
  return (name: host, url: '${uri.scheme}://$host');
}

/// What a package declares about itself in its own `pubspec.yaml`, read from
/// the resolved on-disk root. This is the only local source for the two facts
/// the SBOM was missing: who supplies it, and what *it* depends on.
class _PackageFacts {
  const _PackageFacts({required this.dependencies, this.sourceUrl});

  /// Names from the package's own `dependencies:` block. Its `dev_dependencies`
  /// are deliberately excluded: they build that package, they are not shipped
  /// inside ours, and pub does not resolve them for a transitive dependency —
  /// listing them would put edges in the graph that no artefact of ours has.
  final List<String> dependencies;

  /// Its declared `repository:`, else `homepage:`.
  final String? sourceUrl;
}

/// Read [dir]'s `pubspec.yaml`. Returns null when there is none (or it will not
/// parse), which keeps `dependsOn` null for that component — "not examined"
/// rather than "no dependencies".
_PackageFacts? _packageFacts(Directory? dir) {
  if (dir == null) return null;
  final file = File.fromUri(dir.uri.resolve('pubspec.yaml'));
  if (!file.existsSync()) return null;
  try {
    final yaml = loadYaml(file.readAsStringSync());
    if (yaml is! YamlMap) return null;
    final deps = yaml['dependencies'];
    return _PackageFacts(
      dependencies: deps is YamlMap
          ? deps.keys.map((k) => k.toString()).toList()
          : const [],
      sourceUrl: yaml['repository']?.toString() ?? yaml['homepage']?.toString(),
    );
  } on Object {
    return null;
  }
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
    this.supplier,
    this.supplierUrl,
    this.dependsOn,
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

  /// NTIA minimum element "Supplier Name": the entity that supplies this
  /// component. **Derived, never invented** — see [supplierFromUrl] for the
  /// rule and [supplierUrl] for the declaration it was derived from. Null when
  /// no local source of truth names one; an absent field says "we do not know",
  /// which is the honest answer and the one a consumer can act on.
  final String? supplier;

  /// The declared URL [supplier] was derived from, so the derivation is
  /// checkable rather than asserted.
  final String? supplierUrl;

  /// The [ref]s of the components this one depends on.
  ///
  /// The distinction between `null` and `[]` is load-bearing and is carried
  /// through into both output formats: `[]` means "we read this component's own
  /// manifest and it declares no dependencies", `null` means "we have no
  /// manifest for it, so we cannot say". CycloneDX gives those two the same
  /// meanings (an omitted `dependencies` entry is "unknown"), so a consumer is
  /// never told an unexamined component is a leaf.
  final List<String>? dependsOn;

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

  /// Total number of dependency edges in the graph — the number the SBOM tests
  /// and the Markdown summary quote, so "the graph is one layer deep" is a
  /// claim that can be checked instead of assumed.
  int get edgeCount => all.fold(0, (n, c) => n + (c.dependsOn?.length ?? 0));
}

// ---------------------------------------------------------------------------
// Inventory assembly
// ---------------------------------------------------------------------------

/// Read every source and return the sorted inventory. Runs from the repo root.
Inventory buildInventory() {
  final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
  final appVersion = pubspec['version'].toString();

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

  // What the application itself pulls in: the packages pubspec.yaml names
  // directly, plus everything it bundles that no package pulled in for it (the
  // vendored JS, the fonts, the build SDKs). Those last three would otherwise
  // sit in the document in no relation at all, and "shipped but unreferenced"
  // is exactly the state that makes an SBOM unusable for impact questions.
  final rootEdges =
      components
          .where(
            (c) => c.group == 'dart-package' || c.group == 'vendored-fork'
                ? c.isDirect
                : true,
          )
          .map((c) => c.ref)
          .toList()
        ..sort();

  final root = SbomComponent(
    ref: 'ocideck@$appVersion',
    group: 'application',
    type: 'application',
    name: 'ocideck',
    version: appVersion,
    license: 'EUPL-1.2',
    purl: 'pkg:generic/ocideck@$appVersion',
    // The publisher named in the header of every document under docs/. The one
    // supplier in this file that is stated rather than derived, because it is
    // ours to state.
    supplier: 'Stichting LibreKAT',
    supplierUrl: 'https://librekat.nl',
    dependsOn: rootEdges,
    note: pubspec['description']?.toString(),
  );

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
///
/// Every package carries **its own** dependency edges, read from its own
/// `pubspec.yaml` in the resolved package root and narrowed to the names pub
/// actually resolved. pubspec.lock is a flat list — it says what is in the
/// build, not who pulled it in — so a graph built from the lock file alone is
/// one layer deep and leaves every transitive package hanging in no relation at
/// all. That is what this repo shipped until now: 46 edges over 200 components,
/// 153 of them unreferenced. An unreferenced component cannot be reasoned about
/// ("can I drop this?", "what reaches the parser that just got a CVE?"), which
/// is most of what a dependency graph is for.
List<SbomComponent> _dartPackages() {
  final lock = loadYaml(File('pubspec.lock').readAsStringSync()) as YamlMap;
  final packages = lock['packages'] as YamlMap;
  final roots = _packageRoots();

  // Pass 1: the ref each package name resolves to, so pass 2 can turn a
  // declared dependency name into an edge to a component that really exists.
  final refByName = <String, String>{};
  for (final entry in packages.entries) {
    final name = entry.key.toString();
    final data = entry.value as YamlMap;
    final version = data['version'].toString();
    final source = data['source'].toString();
    refByName[name] = switch (source) {
      'hosted' => 'pkg:pub/$name@$version',
      'path' => 'fork:$name@$version',
      _ => '$source:$name@$version',
    };
  }

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

    final facts = _packageFacts(root);
    final edges = resolveEdges(facts?.dependencies, refByName);
    final fork = _forkOrigins[name];
    // A fork's upstream URL is the stronger statement of origin than whatever
    // the vendored copy's own pubspec still says, so it wins where we have one;
    // an SDK-shipped package is supplied by that SDK whatever its own pubspec
    // links to, which also keeps all five Flutter-SDK packages on one supplier.
    final supplier = supplierFromUrl(
      fork?.vcs ??
          (source == 'sdk' ? _sdkVcsUrls[desc?.toString()] : null) ??
          facts?.sourceUrl,
    );

    if (source == 'hosted') {
      final descMap = desc as YamlMap;
      final host = descMap['url'].toString();
      out.add(
        SbomComponent(
          ref: refByName[name]!,
          group: 'dart-package',
          type: 'library',
          name: name,
          version: version,
          purl: 'pkg:pub/$name@$version',
          sha256: descMap['sha256']?.toString(),
          downloadUrl: '$host/packages/$name/versions/$version',
          license: license,
          scope: scope,
          supplier: supplier?.name,
          supplierUrl: supplier?.url,
          dependsOn: edges,
        ),
      );
    } else if (source == 'path') {
      final dir = Directory('third_party/$name');
      out.add(
        SbomComponent(
          ref: refByName[name]!,
          group: 'vendored-fork',
          type: 'library',
          name: name,
          version: version,
          license: license,
          sha256: dir.existsSync() ? forkTreeHash(dir) : null,
          vcsUrl: fork == null
              ? null
              : fork.subdir.isEmpty
              ? '${fork.vcs}/tree/${fork.revision}'
              : '${fork.vcs}/tree/${fork.revision}/${fork.subdir}',
          upstreamRevision: fork?.revision,
          scope: scope,
          supplier: supplier?.name,
          supplierUrl: supplier?.url,
          dependsOn: edges,
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
          ref: refByName[name]!,
          group: 'dart-package',
          type: 'library',
          name: name,
          version: version,
          license: license,
          scope: scope,
          supplier: supplier?.name,
          supplierUrl: supplier?.url,
          dependsOn: edges,
          note: 'Source: $source.',
        ),
      );
    }
  }
  return out;
}

/// Turn declared dependency [names] into component refs, dropping any name that
/// pub did not resolve into this build.
///
/// Returns null for null input, preserving "not examined" — see
/// [SbomComponent.dependsOn]. A name with no ref is dropped rather than
/// invented: it means the dependency is conditional or dev-only and no artefact
/// of ours contains it, and a dangling ref would make the document invalid.
List<String>? resolveEdges(List<String>? names, Map<String, String> refByName) {
  if (names == null) return null;
  final refs = <String>{};
  for (final n in names) {
    final ref = refByName[n];
    if (ref != null) refs.add(ref);
  }
  final sorted = refs.toList()..sort();
  return sorted;
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
  final seenAssets = <String>{};
  for (final family in fonts) {
    final familyName = family['family'].toString();
    final assets = (family['fonts'] as YamlList?) ?? const [];
    for (final f in assets) {
      final asset = f['asset'].toString();
      // Multiple family names can point to the same physical file (e.g. the
      // `monospace` alias and `Roboto Mono` both use RobotoMono-Variable.ttf).
      // One SBOM component per file, not per alias — the bom-ref is
      // `font:$asset` and a duplicate would fail the uniqueness test.
      if (!seenAssets.add(asset)) continue;
      final file = File(asset);
      final sha = file.existsSync()
          ? sha256.convert(file.readAsBytesSync()).toString()
          : null;
      final base = asset.split('/').last;
      final holder = _fontCopyrightHolder(familyName);
      out.add(
        SbomComponent(
          ref: 'font:$asset',
          group: 'font',
          type: 'file',
          name: familyName,
          purl: 'pkg:generic/${Uri.encodeComponent(familyName)}',
          sha256: sha,
          license: 'OFL-1.1',
          supplier: holder?.name,
          supplierUrl: holder?.url,
          // A font file has no manifest of its own, but "a .ttf depends on
          // nothing" is a fact and not a gap, so this is an empty list rather
          // than an unknown.
          dependsOn: const [],
          note: 'Bundled font file assets/$base.',
        ),
      );
    }
  }
  return out;
}

/// The copyright holder a bundled font's OFL text names, as
/// `Copyright 2011 The Roboto Project Authors (https://…)`.
///
/// The licence files in `assets/fonts/` are shipped alongside the fonts and are
/// the authoritative statement of who the font comes from — no table of font
/// vendors is needed, and none is kept. The family is matched against the
/// copyright line, so adding a font with its OFL text is enough; adding one
/// without simply leaves the supplier absent.
///
/// The match checks for `<family> Project` (case-insensitive) rather than just
/// `<family>`, because a bare `contains` makes 'Roboto' match both
/// "The Roboto Project Authors" and "The Roboto Mono Project Authors" — and
/// which one `listSync()` returns first differs between macOS and Linux.
({String name, String url})? _fontCopyrightHolder(String family) {
  final dir = Directory('assets/fonts');
  if (!dir.existsSync()) return null;
  final needle = '$family Project'.toLowerCase();
  for (final entity in dir.listSync()) {
    if (entity is! File || !entity.path.toLowerCase().endsWith('.txt')) {
      continue;
    }
    final head = entity.readAsStringSync();
    final m = RegExp(
      r'Copyright\s+\d{4}\s+(.+?)\s*\((https?://[^)\s]+)\)',
    ).firstMatch(head);
    if (m == null) continue;
    final holder = m.group(1)!.trim();
    if (!holder.toLowerCase().contains(needle)) continue;
    return (name: holder, url: m.group(2)!);
  }
  return null;
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
        final supplier = supplierFromUrl(_sdkVcsUrls['flutter']);
        out.add(
          SbomComponent(
            ref: 'sdk:flutter@$version',
            group: 'sdk',
            type: 'framework',
            name: 'flutter',
            version: version,
            license: 'BSD-3-Clause',
            downloadUrl: 'https://flutter.dev',
            vcsUrl: _sdkVcsUrls['flutter'],
            supplier: supplier?.name,
            supplierUrl: supplier?.url,
            note: 'Pinned build SDK (.tool-versions).',
          ),
        );
      }
    }
  }

  final sdkConstraint = (pubspec['environment'] as YamlMap?)?['sdk']
      ?.toString();
  if (sdkConstraint != null) {
    final supplier = supplierFromUrl(_sdkVcsUrls['dart']);
    out.add(
      SbomComponent(
        ref: 'sdk:dart@$sdkConstraint',
        group: 'sdk',
        type: 'framework',
        name: 'dart',
        version: sdkConstraint,
        license: 'BSD-3-Clause',
        downloadUrl: 'https://dart.dev',
        vcsUrl: _sdkVcsUrls['dart'],
        supplier: supplier?.name,
        supplierUrl: supplier?.url,
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
    if (c.supplier != null)
      'supplier': {
        'name': c.supplier,
        if (c.supplierUrl != null) 'url': [c.supplierUrl],
      },
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
    'dependencies': dependencyGraph(inv),
  };
  return _jsonEncoder.convert(bom);
}

/// The CycloneDX `dependencies` array: one entry per component whose own
/// dependencies we established, the root included.
///
/// A component with an unread manifest gets **no entry**, which CycloneDX reads
/// as "unknown". Emitting `dependsOn: []` for it would claim we checked and
/// found none — the same silent over-claim as a one-layer graph, only quieter.
List<Map<String, dynamic>> dependencyGraph(Inventory inv) => [
  for (final c in inv.all)
    if (c.dependsOn != null) {'ref': c.ref, 'dependsOn': c.dependsOn},
];

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
    // NTIA minimum element. Absent — not `NOASSERTION` — where no local source
    // names one: SPDX treats an omitted supplier and an explicit "no assertion"
    // the same way, and writing out a name we do not have is the one thing that
    // would make this field worse than empty.
    if (c.supplier != null) 'supplier': 'Organization: ${c.supplier}',
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
    // The full graph, not just the root's own row: every component that
    // declares dependencies gets its own DEPENDS_ON edges, so a reader can walk
    // from a vulnerable leaf back up to what pulls it in.
    for (final c in all)
      for (final dep in c.dependsOn ?? const <String>[])
        {
          'spdxElementId': ids[c.ref]!,
          'relationshipType': 'DEPENDS_ON',
          'relatedSpdxElement': ids[dep]!,
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
  b.writeln('| Component | Version | Licence | Supplier | Source |');
  b.writeln('| --- | --- | --- | --- | --- |');
  for (final c in items) {
    final scope = c.scope != null ? ' _(${c.scope})_' : '';
    b.writeln(
      '| ${c.name}$scope | ${c.version ?? '—'} | ${c.license} '
      '| ${c.supplier ?? '—'} | ${_sourceHint(c)} |',
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
  final unknownSupplier = inv.all.where((c) => c.supplier == null).length;
  b.writeln(
    'This is **${inv.root.name} ${inv.root.version}** (licence '
    '${inv.root.license}) and every third-party component it ships '
    '(${inv.components.length} in total), direct and transitive — the '
    'inventory the EU Cyber Resilience Act (Reg. (EU) 2024/2847, Annex I '
    'Part II §1) requires.\n',
  );
  b.writeln(
    'The JSON documents carry **${inv.edgeCount} dependency relations** between '
    'these components: each package declares its own dependencies, so the graph '
    'can be walked from a leaf back to what pulls it in. '
    '${unknownSupplier == 0 ? 'Every component names a supplier.' : '$unknownSupplier '
              'component(s) name no supplier — no local source of truth states one, '
              'and the field is left empty rather than guessed.'}\n',
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
