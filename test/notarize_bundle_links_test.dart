import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// De koppelingscontrole in `scripts/notarize_macos.sh` (#2115).
///
/// v0.6.4 is getekend, genotariseerd en gestapeld met een load command
/// (`@rpath/PDFium.framework/PDFium`) dat op schijf alleen als
/// `PDFium.framework/pdfium` bestond. Op een hoofdletterongevoelig volume
/// slaagt `test -e` daarop, en dyld op macOS 27 weigert het. De echte
/// bashfuncties draaien hier tegen een nagebouwde bundel; alleen `otool` en
/// `file` zijn vervangen door scripts die vaste uitvoer geven, zodat de toets
/// geen Mach-O hoeft te compileren en ook op de Linux-poort loopt.
///
/// Op een hoofdlettergevoelig bestandssysteem (Linux) is een verkeerd
/// geschreven verwijzing simpelweg afwezig; de uitslag is dan hetzelfde
/// (fout), alleen de diagnose verschilt. De toetsen kijken daarom naar de
/// status en de genoemde verwijzing, niet naar de diagnosetekst.
void main() {
  const script = 'scripts/notarize_macos.sh';
  final skipOnWindows = Platform.isWindows
      ? 'notarize_macos.sh draait alleen op macOS/Linux, niet onder Windows Git Bash'
      : null;

  String allFunctionDefinitions() {
    final lines = File(script).readAsStringSync().split('\n');
    final out = <String>[];
    final open = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*\(\)\s*\{');
    for (var i = 0; i < lines.length; i++) {
      if (!open.hasMatch(lines[i])) continue;
      for (; i < lines.length; i++) {
        out.add(lines[i]);
        if (RegExp(r'^\}\s*$').hasMatch(lines[i])) break;
      }
    }
    return out.join('\n');
  }

  /// Bouwt een bundel met één hoofdbinary en twee frameworks, waarvan
  /// pdfium.framework de echte lay-out heeft: Versions/A/pdfium, een
  /// Versions/Current-symlink en een symlink bovenin. [deps] zijn de
  /// verwijzingen die de nep-otool voor het hoofdbinary rapporteert.
  ({Directory dir, String app}) buildFixture(List<String> deps) {
    final dir = Directory.systemTemp.createTempSync('ocideck-bundle-links-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final app = '${dir.path}/OciDeck.app';
    final macos = Directory('$app/Contents/MacOS')..createSync(recursive: true);
    final fw = Directory('$app/Contents/Frameworks')
      ..createSync(recursive: true);
    final main = File('${macos.path}/OciDeck')..writeAsStringSync('binary');
    Process.runSync('chmod', ['755', main.path]);
    File('${main.path}.deps').writeAsStringSync('${deps.join('\n')}\n');

    Directory('${fw.path}/pdfium.framework/Versions/A')
        .createSync(recursive: true);
    File('${fw.path}/pdfium.framework/Versions/A/pdfium')
        .writeAsStringSync('dylib');
    Process.runSync('chmod', [
      '755',
      '${fw.path}/pdfium.framework/Versions/A/pdfium',
    ]);
    File('${fw.path}/pdfium.framework/Versions/A/pdfium.deps')
        .writeAsStringSync('');
    Link('${fw.path}/pdfium.framework/Versions/Current').createSync('A');
    Link('${fw.path}/pdfium.framework/pdfium')
        .createSync('Versions/Current/pdfium');

    Directory('${fw.path}/Foo.framework/Versions/A').createSync(recursive: true);
    File('${fw.path}/Foo.framework/Versions/A/Foo').writeAsStringSync('dylib');
    Process.runSync('chmod', ['755', '${fw.path}/Foo.framework/Versions/A/Foo']);
    File('${fw.path}/Foo.framework/Versions/A/Foo.deps').writeAsStringSync('');

    // Nep-otool: -l geeft de twee rpaths die Flutter's Runner altijd draagt,
    // -L geeft de kopregel plus wat er in <binary>.deps staat. Nep-file noemt
    // alles met een .deps-buur een Mach-O.
    final bin = Directory('${dir.path}/bin')..createSync();
    File('${bin.path}/otool')
      ..writeAsStringSync('''#!/usr/bin/env bash
case "\$1" in
  -l) printf '          cmd LC_RPATH\\n         path @executable_path/../Frameworks (offset 12)\\n'
      printf '          cmd LC_RPATH\\n         path @loader_path/Frameworks (offset 12)\\n' ;;
  -L) printf '%s:\\n' "\$2"
      [ -f "\$2.deps" ] && while read -r d || [ -n "\$d" ]; do
        [ -n "\$d" ] && printf '\\t%s (compatibility version 0.0.0, current version 0.0.0)\\n' "\$d"
      done <"\$2.deps" ;;
esac
''')
      ..setPermissions();
    File('${bin.path}/file')
      ..writeAsStringSync('''#!/usr/bin/env bash
[ -f "\$2.deps" ] && echo "Mach-O 64-bit executable arm64" || echo "data"
''')
      ..setPermissions();
    return (dir: dir, app: app);
  }

  ProcessResult check(({Directory dir, String app}) fx) {
    final harness = File('${fx.dir.path}/harness.sh')
      ..writeAsStringSync('''
set -uo pipefail
export PATH="${fx.dir.path}/bin:\$PATH"
${allFunctionDefinitions()}
check_bundle_links "${fx.app}"
''');
    return Process.runSync('bash', [harness.path]);
  }

  test('kloppende verwijzingen, ook via de Versions/Current-symlink', () {
    final fx = buildFixture([
      '@rpath/pdfium.framework/pdfium',
      '@rpath/Foo.framework/Versions/A/Foo',
      '@executable_path/../Frameworks/Foo.framework/Versions/A/Foo',
      '/usr/lib/libSystem.B.dylib',
    ]);
    final r = check(fx);
    expect(r.exitCode, 0, reason: 'stderr: ${r.stderr}');
    expect(r.stderr, isEmpty);
  }, skip: skipOnWindows);

  test('de v0.6.4-verwijzing met hoofdletters valt om', () {
    final fx = buildFixture(['@rpath/PDFium.framework/PDFium']);
    final r = check(fx);
    expect(r.exitCode, 1, reason: 'stderr: ${r.stderr}');
    expect(r.stderr, contains('FOUT Contents/MacOS/OciDeck: @rpath/PDFium.framework/PDFium'));
  }, skip: skipOnWindows);

  test('ook een mapcomponent met andere schrijfwijze valt om', () {
    // dyld kijkt alleen naar de bladnaam; deze controle eist bewust élke
    // component, zodat de bundel overal dezelfde spelling draagt en een
    // volgende toolchain die strenger wordt hier niets nieuws vindt.
    final fx = buildFixture(['@rpath/PDFium.framework/pdfium']);
    final r = check(fx);
    expect(r.exitCode, 1, reason: 'stderr: ${r.stderr}');
    expect(r.stderr, contains('@rpath/PDFium.framework/pdfium'));
  }, skip: skipOnWindows);

  test('een verwijzing die nergens oplost valt om en wordt genoemd', () {
    final fx = buildFixture([
      '@rpath/pdfium.framework/pdfium',
      '@rpath/Bar.framework/Bar',
    ]);
    final r = check(fx);
    expect(r.exitCode, 1, reason: 'stderr: ${r.stderr}');
    expect(r.stderr, contains('@rpath/Bar.framework/Bar'));
    expect(r.stderr, contains('nergens op'));
    expect(r.stderr, isNot(contains('pdfium.framework/pdfium')));
  }, skip: skipOnWindows);

  test('twee fouten worden allebei gemeld, in één doorloop', () {
    final fx = buildFixture([
      '@rpath/PDFium.framework/PDFium',
      '@rpath/Bar.framework/Bar',
    ]);
    final r = check(fx);
    expect(r.exitCode, 2, reason: 'stderr: ${r.stderr}');
    expect(r.stderr, contains('@rpath/PDFium.framework/PDFium'));
    expect(r.stderr, contains('@rpath/Bar.framework/Bar'));
  }, skip: skipOnWindows);
}

extension on File {
  void setPermissions() => Process.runSync('chmod', ['755', path]);
}
