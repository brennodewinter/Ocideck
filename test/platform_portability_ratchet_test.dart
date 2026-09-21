import 'package:flutter_test/flutter_test.dart';

import '../tool/check_conventions.dart';

/// Het meetinstrument achter de twee platform-portabiliteitsregels in
/// `tool/check_conventions.dart`:
///
/// * `handJoinedPathExpectsIn` — een `expect` die een door de code opgebouwd
///   pad vergelijkt met een `'${map.path}/bestand'`-literal staat groen op
///   macOS en Linux en breekt op Windows, waar `p.join` een `\` levert. De
///   eerste Windows-run van zo'n test is de tag-pijplijn op de
///   GitHub-spiegel, dus de breuk landde drie releases op rij precies op het
///   moment van uitbrengen (v0.6.3–v0.6.5).
/// * `bsdMktempIn` — `mktemp -t naam` is de BSD-vorm; GNU coreutils weigert
///   een sjabloon zonder X's. Zo vielen vier testen op de Gate (Linux)-job
///   van tag v0.6.8.
///
/// Beide zijn pure functies over pad → bron, dus hieronder staan verzonnen
/// bestanden — net als bij `fixed_delay_ratchet_test.dart`.
void main() {
  List<int> meetExpect(String source) =>
      handJoinedPathExpectsIn({
        'test/x_test.dart': source,
      })['test/x_test.dart'] ??
      const <int>[];

  /// De fixtures zijn echte Dart: de parser is de meting, dus een fragment
  /// dat niet compileert zou hier niets bewijzen.
  String testBestand(String body) =>
      'void main() {\n  test(\'x\', () {\n$body\n  });\n}\n';

  group('handJoinedPathExpectsIn', () {
    test('een handgeplakte pad-vergelijking wordt gevonden', () {
      expect(
        meetExpect(
          testBestand("    expect(dest?.path, '\${project.path}/images');"),
        ),
        [3],
      );
    });

    test('ook als het anker `.dir` heet', () {
      expect(
        meetExpect(
          testBestand("    expect(result, '\${archive.dir}/foto.png');"),
        ),
        [3],
      );
    });

    test('p.join als verwachting is precies de bedoeling', () {
      expect(
        meetExpect(
          testBestand("    expect(added, p.join(archive.path, 'foto.png'));"),
        ),
        isEmpty,
      );
    });

    test('een project-relatieve literal hoort bij het formaat', () {
      // 'images/photo.png' is een pad ín het Markdown-document en is per
      // definitie met `/`, op elk platform. Die mag de regel niet raken.
      expect(
        meetExpect(
          testBestand("    expect(out.imagePath, 'images/photo.png');"),
        ),
        isEmpty,
      );
    });

    test('een File() met handgeplakt pad in de arrange-stap is oké', () {
      // Dart én Windows accepteren `/` in een pad; alleen de vergelijking
      // breekt. De regel mikt daarom alleen op de verwachte waarde.
      expect(
        meetExpect(
          testBestand(
            "    expect(File('\${dir.path}/logo.png').existsSync(), isTrue);",
          ),
        ),
        isEmpty,
      );
    });

    test('een interpolatie zonder path-anker is geen padvergelijking', () {
      expect(
        meetExpect(testBestand("    expect(label, '\$name/details');")),
        isEmpty,
      );
    });

    test('de treffer staat ook in een geneste callback', () {
      expect(
        meetExpect(
          testBestand('''
    final files = <String>[];
    for (final f in files) {
      expect(f, '\${dir.path}/x');
    }'''),
        ),
        [5],
      );
    });
  });

  group('bsdMktempIn', () {
    List<int> meetSh(String source) =>
        bsdMktempIn({'scripts/x.sh': source})['scripts/x.sh'] ?? const <int>[];

    test('mktemp -t zonder Xs wordt gevonden', () {
      expect(meetSh('#!/bin/sh\nLOG="\$(mktemp -t proef)"\n'), [2]);
    });

    test('mktemp -t mét Xs is dezelfde BSD-vorm en telt evengoed', () {
      // Op GNU is -t verouderd, ook met X's — de uitdrukkelijke padvorm is
      // de enige die op beide werkt.
      expect(meetSh('LOG="\$(mktemp -t proef.XXXXXX)"\n'), [1]);
    });

    test('de uitdrukkelijke padvorm is de bedoeling', () {
      expect(
        meetSh('LOG="\$(mktemp "\${TMPDIR:-/tmp}/proef.XXXXXX")"\n'),
        isEmpty,
      );
    });

    test('mktemp -d is altijd al portable geweest', () {
      expect(meetSh('TMP="\$(mktemp -d)"\n'), isEmpty);
    });

    test('de vorm in commentaar is uitleg, geen aanroep', () {
      expect(meetSh('# gebruik niet: mktemp -t proef\nexit 0\n'), isEmpty);
    });
  });
}
