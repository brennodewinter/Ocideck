// Guards the system libraries the Linux build needs against the plugins that
// demand them.
//
//   dart run tool/check_linux_pkgconfig.dart   (or: make check-linux-deps)
//
// A Flutter plugin asks for a system library on Linux by calling
// `pkg_check_modules(NAME REQUIRED IMPORTED_TARGET <module>)` in its CMake. If
// the module is not installed, `flutter build linux` dies while *generating*
// the build files — before a single file is compiled, and with an error that
// names a pkg-config module rather than a package anyone can apt-install.
//
// Nothing in a `flutter test` run notices that. The nativeapi migration (#1741)
// added such a demand (`ayatana-appindicator3-0.1`), every gate stayed green,
// and the first machine to try a Linux build was the release chain — which is
// how v0.4.9 ended up with no release at all.
//
// So this compares two things that must agree:
//
//   the demands  — re-derived from the resolved plugin sources, via
//                  .dart_tool/package_config.json
//   the promises — .github/linux-pkgconfig-modules.json, which names for each
//                  module the apt package that provides it, whether the build
//                  environments must install it explicitly, and which runtime
//                  package the .deb and the AUR PKGBUILD must depend on
//
// Both directions are fatal. A demand without a promise is the failure above. A
// promise without a demand is a dependency we still install and still make our
// users install, for a reason that no longer exists.
//
// Ceiling: pkg-config is how Flutter's Linux plugins ask for system libraries,
// but not the only way anything can. `find_library`, `find_package`, a bare
// `#include`, or a build script shelling out to a tool are all invisible here.
// Upgrade path is not a cleverer parser but an actual build: the post-merge
// Linux build in .forgejo/workflows/linux-build.yml.
//
// Exit codes: 0 = demands and promises agree
//             1 = they do not (the report names the file to edit)
//             2 = the check could not run (no package_config.json — run
//                 `flutter pub get` — or a malformed manifest)

import 'dart:convert';
import 'dart:io';

const _manifestPath = '.github/linux-pkgconfig-modules.json';
const _packageConfigPath = '.dart_tool/package_config.json';

/// Directory names whose CMake never reaches our build: a plugin's own demo
/// apps and its tests. cnativeapi's `cxx_impl/examples/` requires `openssl`,
/// which our bundle does not link and no build environment needs.
const _ignoredDirs = {
  'example',
  'examples',
  'test',
  'tests',
  'build',
  '.git',
  // The native-assets build tree: dartcv4 compiles OpenCV in here, and OpenCV's
  // own CMake asks pkg-config for a long list of optional codecs that our build
  // never links. Scanning it would report demands nobody makes.
  '.dart_tool',
  '.claude',
};

final _pkgCheckModules = RegExp(
  r'pkg_check_modules\s*\(([^)]*)\)',
  multiLine: true,
);

/// CMake keywords inside the call that are not module names.
const _cmakeKeywords = {
  'REQUIRED',
  'IMPORTED_TARGET',
  'GLOBAL',
  'QUIET',
  'NO_CMAKE_PATH',
  'NO_CMAKE_ENVIRONMENT_PATH',
};

void main(List<String> args) {
  final manifest = _readJson(_manifestPath);
  final packageConfig = _readJson(_packageConfigPath);
  if (manifest == null || packageConfig == null) exit(2);

  final promised = _promisedModules(manifest);
  final demanded = _demandedModules(packageConfig);

  final problems = <String>[
    ..._missingPromises(demanded, promised),
    ..._stalePromises(demanded, promised),
    ..._undeclaredInBuildEnvironments(manifest),
    ..._undeclaredAtRuntime(manifest),
  ];

  if (problems.isEmpty) {
    stdout.writeln(
      'linux pkg-config OK: ${demanded.length} required module(s) across '
      '${demanded.values.expand((e) => e).toSet().length} package(s), all '
      'declared.',
    );
    return;
  }
  for (final problem in problems) {
    stderr.writeln(problem);
  }
  exit(1);
}

Map<String, dynamic>? _readJson(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('$path ontbreekt — draai `flutter pub get`.');
    return null;
  }
  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  } on FormatException catch (e) {
    stderr.writeln('$path is geen geldige JSON: $e');
    return null;
  }
}

/// Module name → the manifest entry that promises to provide it.
Map<String, Map<String, dynamic>> _promisedModules(Map<String, dynamic> m) {
  final entries = (m['modules'] as List).cast<Map<String, dynamic>>();
  return {for (final e in entries) e['module'] as String: e};
}

/// Module name → the packages whose CMake requires it.
Map<String, Set<String>> _demandedModules(Map<String, dynamic> packageConfig) {
  final demanded = <String, Set<String>>{};
  final packages = (packageConfig['packages'] as List)
      .cast<Map<String, dynamic>>();
  for (final pkg in packages) {
    final root = _packageRoot(pkg['rootUri'] as String);
    if (root == null || !root.existsSync()) continue;
    for (final module in _requiredModulesIn(root)) {
      demanded.putIfAbsent(module, () => {}).add(pkg['name'] as String);
    }
  }
  return demanded;
}

/// Resolves a package_config `rootUri`, which is absolute for pub-cache
/// packages and relative to `.dart_tool/` for path dependencies.
Directory? _packageRoot(String rootUri) {
  final uri = Uri.parse(rootUri);
  if (uri.hasScheme) return Directory.fromUri(uri);
  return Directory(Uri.directory('.dart_tool').resolveUri(uri).toFilePath());
}

Set<String> _requiredModulesIn(Directory root) {
  final modules = <String>{};
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('CMakeLists.txt')) continue;
    if (_isIgnored(root, entity)) continue;
    modules.addAll(_requiredModulesInFile(entity));
  }
  return modules;
}

bool _isIgnored(Directory root, File file) {
  final relative = file.path.substring(root.path.length);
  return relative
      .split(Platform.pathSeparator)
      .any((segment) => _ignoredDirs.contains(segment));
}

Set<String> _requiredModulesInFile(File file) {
  final modules = <String>{};
  final String text;
  try {
    text = file.readAsStringSync();
  } on FileSystemException {
    return modules; // unreadable (a stale symlink in the cache) is not a demand
  }
  for (final match in _pkgCheckModules.allMatches(text)) {
    final words = match.group(1)!.split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    if (!words.contains('REQUIRED')) continue;
    // words[0] is the result-variable prefix, the rest are keywords or modules.
    for (final word in words.skip(1)) {
      if (_cmakeKeywords.contains(word)) continue;
      if (word.startsWith(r'$')) continue; // a variable, not a literal module
      modules.add(_withoutVersionConstraint(word));
    }
  }
  return modules;
}

/// `libsecret-1>=0.18.4` names the module `libsecret-1`; the constraint is not
/// part of its name and never appears in a package name.
String _withoutVersionConstraint(String module) =>
    module.split(RegExp(r'[<>=]')).first;

List<String> _missingPromises(
  Map<String, Set<String>> demanded,
  Map<String, Map<String, dynamic>> promised,
) => [
  for (final module in demanded.keys.where((m) => !promised.containsKey(m)))
    'Plugin(s) ${demanded[module]!.join(', ')} require the pkg-config module '
        '`$module`, which $_manifestPath does not name.\n'
        '  → Add it there with the apt package that provides it, and install '
        'that package in every build environment listed in the manifest.\n'
        '  → Without this, `flutter build linux` fails in CMake — on the '
        'release chain, not here.',
];

List<String> _stalePromises(
  Map<String, Set<String>> demanded,
  Map<String, Map<String, dynamic>> promised,
) => [
  for (final module in promised.keys.where((m) => !demanded.containsKey(m)))
    'No plugin requires `$module` any more, but $_manifestPath still promises '
        'it.\n'
        '  → Remove it there, from the apt lines, and from the runtime '
        'dependency lists: we are making users install a library we no longer '
        'link.',
];

/// An environment is a *composition*, not a file: the Forgejo release job
/// installs part of what it needs and inherits the rest from the prebaked CI
/// image. So each environment lists every file that can carry the package, and
/// one of them naming it is enough.
List<String> _undeclaredInBuildEnvironments(Map<String, dynamic> manifest) {
  final problems = <String>[];
  final environments = (manifest['buildEnvironments'] as List)
      .cast<Map<String, dynamic>>();
  for (final entry in _explicitEntries(manifest)) {
    final package = entry['apt'] as String;
    for (final environment in environments) {
      final files = (environment['files'] as List).cast<String>();
      if (files.any((path) => _fileContains(path, package))) continue;
      problems.add(
        'Build environment "${environment['name']}" never installs `$package`, '
        'which provides the required module `${entry['module']}`.\n'
        '  → Add it in one of: ${files.join(', ')}.',
      );
    }
  }
  return problems;
}

List<String> _undeclaredAtRuntime(Map<String, dynamic> manifest) {
  final problems = <String>[];
  final declarations = (manifest['runtimeDeclarations'] as Map)
      .cast<String, String>();
  for (final entry in _explicitEntries(manifest)) {
    final runtime = (entry['runtime'] as Map?)?.cast<String, String>();
    if (runtime == null) continue;
    for (final kind in runtime.keys) {
      final path = declarations[kind];
      if (path == null || _fileContains(path, runtime[kind]!)) continue;
      problems.add(
        '$path does not depend on `${runtime[kind]}`.\n'
        '  → The bundle links `${entry['module']}` but does not carry it, so '
        'without this the package installs and the app then fails to start.',
      );
    }
  }
  return problems;
}

Iterable<Map<String, dynamic>> _explicitEntries(
  Map<String, dynamic> manifest,
) => (manifest['modules'] as List).cast<Map<String, dynamic>>().where(
  (e) => e['explicit'] == true,
);

/// Looks for [needle] in [path], **outside comments**.
///
/// Every file this gate reads — YAML workflows, the packager, the PKGBUILD, the
/// setup guide — comments with `#`. Matching the raw text would let the prose
/// that *explains* a package stand in for actually installing it: delete the
/// apt argument, leave the comment above it, and a naive check stays green. So
/// the comment half of every line is dropped before looking.
bool _fileContains(String path, String needle) {
  final file = File(path);
  if (!file.existsSync()) return false;
  return file
      .readAsLinesSync()
      .map((line) => line.split('#').first)
      .any((code) => code.contains(needle));
}
