import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regressie voor #2296: de notarisatie-preflight moet de notarytool-fout
/// classificeren en alleen het herstelpad tonen dat erbij hoort.
///
/// Bij v0.6.x liet `notarytool history` een HTTP 403 zien — een vereiste
/// Apple-overeenkomst ontbrak — maar het script adviseerde alsnog
/// store-credentials, dat hooguit een keychain-profiel herschrijft en een
/// juridische overeenkomst nooit kan accepteren.
void main() {
  const script = 'scripts/notarize_macos.sh';
  final skip = Platform.isWindows
      ? 'notarize_macos.sh draait alleen op macOS/Linux'
      : (!Platform.isMacOS ? 'de preflight eist uname==Darwin' : null);

  /// Draait de echte --preflight met alle externe commando's vervangen door
  /// vaste uitvoer; `xcrun notarytool history` faalt met [notaryOut].
  Future<ProcessResult> runPreflight(String notaryOut) async {
    final dir = Directory.systemTemp.createTempSync('ocideck-notary-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final bin = Directory('${dir.path}/bin')..createSync();
    File('${dir.path}/notary.txt').writeAsStringSync(notaryOut);
    File('${bin.path}/security').writeAsStringSync('''
#!/usr/bin/env bash
if [ "\$1 \$2" = "default-keychain -d" ]; then echo "/tmp/fake.keychain-db"; fi
if [ "\$1" = "find-identity" ]; then
  echo '  1) AA "Developer ID Application: Brenno de Winter (AMT83P4B3L)"'
fi
exit 0
''');
    File('${bin.path}/xcrun').writeAsStringSync('''
#!/usr/bin/env bash
if [ "\$1" = "notarytool" ]; then cat "\$FAKE_NOTARY_OUT"; exit 1; fi
exit 0
''');
    for (final c in [
      'flutter',
      'codesign',
      'ditto',
      'otool',
      'install_name_tool',
    ]) {
      File('${bin.path}/$c').writeAsStringSync('#!/usr/bin/env bash\nexit 0\n');
    }
    Process.runSync('chmod', ['-R', '+x', bin.path]);
    return Process.run(
      'bash',
      [File(script).absolute.path, '--preflight'],
      environment: {
        ...Platform.environment,
        'PATH': '${bin.path}:${Platform.environment['PATH'] ?? ''}',
        'FAKE_NOTARY_OUT': '${dir.path}/notary.txt',
      },
      workingDirectory: Directory.current.path,
    );
  }

  test('een overeenkomst-403 wijst naar de Account Holder, niet naar '
      'store-credentials', () async {
    final r = await runPreflight(
      'Error: HTTP status code: 403. A required agreement is missing or '
      'has expired.',
    );
    expect(r.exitCode, 1);
    expect(r.stderr, contains('required agreement is missing or has expired'));
    expect(r.stderr, contains('Account Holder'));
    expect(r.stderr, contains('accepteren'));
    // store-credentials is hier uitdrukkelijk níet het herstelpad.
    expect(r.stderr, isNot(contains('Herstel met')));
  }, skip: skip);

  test(
    'een ontbrekend profiel krijgt wél het store-credentials-advies',
    () async {
      final r = await runPreflight(
        "Error: No keychain profile named 'ocideck-notary' found.",
      );
      expect(r.exitCode, 1);
      expect(r.stderr, contains('store-credentials'));
      expect(r.stderr, isNot(contains('Account Holder')));
    },
    skip: skip,
  );

  test(
    'een authenticatiefout wijst naar Apple-ID en app-specifiek wachtwoord',
    () async {
      final r = await runPreflight(
        'Error: HTTP status code: 401. Invalid credentials.',
      );
      expect(r.exitCode, 1);
      expect(r.stderr, contains('app-specifiek'));
      expect(r.stderr, isNot(contains('Account Holder')));
    },
    skip: skip,
  );

  test(
    'een onbekende fout toont de uitvoer zonder verzonnen oorzaak',
    () async {
      final r = await runPreflight('Error: something entirely unexpected');
      expect(r.exitCode, 1);
      expect(r.stderr, contains('something entirely unexpected'));
      expect(r.stderr, contains('Geen bekende oorzaak herkend'));
      expect(r.stderr, isNot(contains('Account Holder')));
      expect(r.stderr, isNot(contains('Herstel met')));
    },
    skip: skip,
  );
}
