import 'dart:io';

// Positieve en negatieve gevallen voor de lokale metadata-uitzondering (#3068).

Future<Process> localNumericMetadata(String real) {
  // ok: ocideck-subproces-buiten-de-gitlaag
  return Process.start('/usr/bin/stat', [
    '-Lc',
    '%u:%a',
    '--',
    '/proc/self',
    real,
  ], includeParentEnvironment: false);
}

Future<Process> inheritedEnvironment(String real) {
  // ruleid: ocideck-subproces-buiten-de-gitlaag
  return Process.start('/usr/bin/stat', [
    '-Lc',
    '%u:%a',
    '--',
    '/proc/self',
    real,
  ], includeParentEnvironment: true);
}

Future<Process> implicitEnvironment(String real) {
  // ruleid: ocideck-subproces-buiten-de-gitlaag
  return Process.start('/usr/bin/stat', [
    '-Lc',
    '%u:%a',
    '--',
    '/proc/self',
    real,
  ]);
}

Future<Process> shellEnabled(String real) {
  // ruleid: ocideck-subproces-buiten-de-gitlaag
  return Process.start(
    '/usr/bin/stat',
    ['-Lc', '%u:%a', '--', '/proc/self', real],
    includeParentEnvironment: false,
    runInShell: true,
  );
}

Future<Process> customEnvironment(String real) {
  // ruleid: ocideck-subproces-buiten-de-gitlaag
  return Process.start(
    '/usr/bin/stat',
    ['-Lc', '%u:%a', '--', '/proc/self', real],
    includeParentEnvironment: false,
    environment: {'LD_PRELOAD': '/tmp/fixture.so'},
  );
}

Future<Process> differentExecutable(String real) {
  // ruleid: ocideck-subproces-buiten-de-gitlaag
  return Process.start('/bin/sh', [
    '-Lc',
    '%u:%a',
    '--',
    '/proc/self',
    real,
  ], includeParentEnvironment: false);
}

Future<Process> namedOwnerLookup(String real) {
  // ruleid: ocideck-subproces-buiten-de-gitlaag
  return Process.start('/usr/bin/stat', [
    '-Lc',
    '%U:%a',
    '--',
    '/proc/self',
    real,
  ], includeParentEnvironment: false);
}

Future<ProcessResult> runInsteadOfStart(String real) {
  // ruleid: ocideck-subproces-buiten-de-gitlaag
  return Process.run('/usr/bin/stat', [
    '-Lc',
    '%u:%a',
    '--',
    '/proc/self',
    real,
  ], includeParentEnvironment: false);
}

Future<Process> extraPath(String real) {
  // ruleid: ocideck-subproces-buiten-de-gitlaag
  return Process.start('/usr/bin/stat', [
    '-Lc',
    '%u:%a',
    '--',
    '/proc/self',
    real,
    'other',
  ], includeParentEnvironment: false);
}

Future<Process> dynamicFormat(String real, String format) {
  // ruleid: ocideck-subproces-buiten-de-gitlaag
  return Process.start('/usr/bin/stat', [
    '-Lc',
    format,
    '--',
    '/proc/self',
    real,
  ], includeParentEnvironment: false);
}

Future<Process> dynamicExecutable(String real, String program) {
  // ruleid: ocideck-subproces-buiten-de-gitlaag
  return Process.start(program, [
    '-Lc',
    '%u:%a',
    '--',
    '/proc/self',
    real,
  ], includeParentEnvironment: false);
}

Future<Process> missingOptionTerminator(String real) {
  // ruleid: ocideck-subproces-buiten-de-gitlaag
  return Process.start('/usr/bin/stat', [
    '-Lc',
    '%u:%a',
    '/proc/self',
    real,
  ], includeParentEnvironment: false);
}

Future<Process> differentOwnerReference(String real) {
  // ruleid: ocideck-subproces-buiten-de-gitlaag
  return Process.start('/usr/bin/stat', [
    '-Lc',
    '%u:%a',
    '--',
    '/tmp/fixture',
    real,
  ], includeParentEnvironment: false);
}
