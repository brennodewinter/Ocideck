import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_version_bump.dart';

/// De guard-toets voor `scripts/release_auto.sh` (#1161).
///
/// Het onbewaakte release-script berekent de volgende versie uit een menukeuze
/// (patch/minor/major) i.p.v. een meegegeven tag. Die berekening ÍS de tag-guard:
/// ze mag alléén een canonieke één-as-stap opleveren — precies de regel die
/// [legalNextVersions] vastlegt en die `make check-version-bump` op de PR
/// afdwingt. Deze test pint dat de bash-rekenkunde en de Dart-regel niet uit
/// elkaar kunnen lopen.
///
/// De `--print-version`-modus is bewust hermetisch (leest alleen `pubspec.yaml`,
/// raakt git noch netwerk), zodat deze test snel en zonder poort-neveneffecten
/// draait.
void main() {
  const script = 'scripts/release_auto.sh';

  // release_auto.sh is een macOS/Unix-maintainertool: hij leunt op de
  // macOS-keychain (`security`), op `codesign`/`ditto` en op `/Applications`, en
  // wordt alleen op de maintainer-Mac en de Linux-CI gedraaid. Onder Windows
  // Git Bash (alleen de mirror-CI, alleen op een v*-tag) viel het script om met
  // exit 1 terwijl macOS/Linux — waar de release écht draait — groen waren. Sla
  // deze bash-toetsen op Windows over i.p.v. een niet-ondersteund draaipunt te
  // toetsen; de Forgejo-poorten die merges gate'n draaien geen Windows.
  final skipOnWindows = Platform.isWindows
      ? 'release_auto.sh draait alleen op macOS/Linux, niet onder Windows Git Bash'
      : null;

  String currentPubspecVersion() {
    for (final line in File('pubspec.yaml').readAsLinesSync()) {
      final m = RegExp(
        r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
      ).firstMatch(line);
      if (m != null) return m.group(1)!;
    }
    fail('geen version: in pubspec.yaml');
  }

  String printVersion(String level) {
    final r = Process.runSync('bash', [script, '--print-version', level]);
    expect(
      r.exitCode,
      0,
      reason: 'release_auto.sh --print-version $level faalde: ${r.stderr}',
    );
    return (r.stdout as String).trim();
  }

  // Trekt de body van een top-level bash-functie uit het script: de regels tussen
  // 'naam() {' en de eerstvolgende regel die enkel '}' is. De functies in
  // release_auto.sh sluiten met een kale '}' op kolom 0, dus dit is exact genoeg
  // zonder een echte bash-parser.
  String functionBody(String name) {
    final lines = File(script).readAsStringSync().split('\n');
    final open = RegExp('^${RegExp.escape(name)}\\(\\)\\s*\\{');
    var start = -1;
    for (var i = 0; i < lines.length; i++) {
      if (open.hasMatch(lines[i])) {
        start = i;
        break;
      }
    }
    if (start < 0) fail('functie $name() niet gevonden in $script');
    for (var i = start + 1; i < lines.length; i++) {
      if (RegExp(r'^\}\s*$').hasMatch(lines[i])) {
        return lines.sublist(start + 1, i).join('\n');
      }
    }
    fail('geen sluitende "}" voor $name() gevonden in $script');
  }

  test(
    'de drie niveaus zijn exact de canonieke bumps van de huidige versie',
    () {
      final current = SemVer.tryParse(currentPubspecVersion())!;
      final patch = printVersion('patch');
      final minor = printVersion('minor');
      final major = printVersion('major');

      // 'v'-prefix eraf; de guard rekent op de kale semver.
      final produced = {
        patch.substring(1),
        minor.substring(1),
        major.substring(1),
      };
      expect(patch, startsWith('v'));
      expect(
        produced,
        legalNextVersions(current),
        reason: 'de menu-rekenkunde wijkt af van de canonieke één-as-regel',
      );
    },
    skip: skipOnWindows,
  );

  test('elk niveau kiest de juiste as', () {
    final current = SemVer.tryParse(currentPubspecVersion())!;
    expect(
      printVersion('patch'),
      'v${current.major}.${current.minor}.${current.patch + 1}',
    );
    expect(printVersion('minor'), 'v${current.major}.${current.minor + 1}.0');
    expect(printVersion('major'), 'v${current.major + 1}.0.0');
  }, skip: skipOnWindows);

  test('zonder niveau weigert --print-version', () {
    final r = Process.runSync('bash', [script, '--print-version']);
    expect(r.exitCode, isNot(0));
    expect(r.stderr.toString(), contains('niveau'));
  }, skip: skipOnWindows);

  // --resume (#9): al deze paden falen hermetisch — vóór git/netwerk — zodat de
  // test snel en zonder poort-neveneffecten blijft.
  test('--resume zonder tag weigert', () {
    final r = Process.runSync('bash', [script, '--resume']);
    expect(r.exitCode, isNot(0));
    expect(r.stderr.toString(), contains('tag'));
  }, skip: skipOnWindows);

  test('een losse tag zonder --resume weigert (typfout-vangnet)', () {
    final r = Process.runSync('bash', [script, 'v9.9.9']);
    expect(r.exitCode, isNot(0));
    expect(r.stderr.toString(), contains('resume'));
  }, skip: skipOnWindows);

  // Statische invariant (leest het script, draait geen bash — dus ook groen op de
  // Windows-mirror-CI). Regressie voor de v0.4.1-release die brak op
  // 'fatal: bad object type'.
  test('tag_and_push fetcht de merge-commit vóór het annoteren van de tag', () {
    // merge_pr merget de PR server-side via de REST-API; de merge-commit bestaat
    // op dat moment alleen op origin. tag_and_push annoteerde daar een tag op
    // ('git tag -a … "$mergesha"') zónder 'm eerst te fetchen, waardoor git tag
    // viel op een object dat de lokale database niet had. De fix is een
    // 'git fetch origin' vóór het taggen; deze poort borgt die volgorde — óók in
    // de --resume-route, die door dezelfde functie loopt.
    final body = functionBody('tag_and_push');
    // Anker op regelbegin (multiline): pak het échte commando, niet het
    // 'git tag -a' dat in de toelichtende comment of in een die-melding staat.
    final fetchIdx = body.indexOf(
      RegExp(r'^\s*git\s+fetch\b.*\borigin\b', multiLine: true),
    );
    final annotateIdx = body.indexOf(
      RegExp(r'^\s*git\s+tag\s+-a\b', multiLine: true),
    );

    expect(
      annotateIdx,
      isNonNegative,
      reason: 'git tag -a niet gevonden in tag_and_push',
    );
    expect(
      fetchIdx,
      isNonNegative,
      reason:
          'tag_and_push fetcht de server-side merge-commit niet met '
          '"git fetch origin"; git tag -a faalt dan met "bad object type" '
          '(zie de v0.4.1-release).',
    );
    expect(
      fetchIdx,
      lessThan(annotateIdx),
      reason:
          'de "git fetch origin" moet vóór "git tag -a" staan, anders is de '
          'merge-commit nog niet lokaal.',
    );
  });

  // De mirror-tag (GitHub-spiegel) is een eigen faalpunt: de origin-push start de
  // Forgejo-CI, maar de Windows-build op de spiegel start pas als de tag ÓÓK op de
  // mirror staat (windows-ophalen dispatcht met --ref $TAG). Faalde de mirror-push,
  // dan mag geen enkele tag-route 'm overslaan — óók --resume niet (die kwam bij een
  // bestaande origin-tag nooit meer langs de mirror-push). Regressie voor die klasse,
  // het zusje van de bad-object-type-bug.
  test('ensure_mirror_tag is idempotent en pusht naar de mirror', () {
    final body = functionBody('ensure_mirror_tag');
    expect(
      body,
      matches(RegExp(r'ls-remote[^\n]*\bmirror\b')),
      reason:
          'ensure_mirror_tag moet eerst toetsen of de tag al op de mirror staat '
          '(idempotent), anders is een tweede run niet veilig.',
    );
    expect(
      body,
      matches(RegExp(r'git\s+push[^\n]*\bmirror\b')),
      reason: 'ensure_mirror_tag moet de tag naar de mirror pushen.',
    );
  });

  test('elke tag-route borgt de mirror-tag', () {
    // Zowel de normale keten (tag_and_push) als de "tag staat al op origin"-tak van
    // --resume (resume_release) moeten de mirror-tag borgen; anders kan een
    // ontbrekende mirror-tag de Windows-build blijvend blokkeren — ook na --resume.
    for (final fn in ['tag_and_push', 'resume_release']) {
      expect(
        functionBody(fn),
        contains('ensure_mirror_tag'),
        reason:
            '$fn moet ensure_mirror_tag aanroepen; zonder dat kan een gefaalde '
            'mirror-push de Windows-build blokkeren zonder herstelroute.',
      );
    }
  });

  test('TAG_PUSHED wordt gezet zodra origin de tag heeft, niet pas na de mirror', () {
    // De origin-push is het punt-van-geen-terugkeer (de release-CI start daar). Een
    // falende mirror-push daarna mag de ERR-trap niet laten zeggen "niets naar
    // buiten" — dus TAG_PUSHED=1 hoort vóór de mirror-stap (ensure_mirror_tag).
    final body = functionBody('tag_and_push');
    final pushedIdx = body.indexOf(
      RegExp(r'^\s*TAG_PUSHED=1', multiLine: true),
    );
    final mirrorIdx = body.indexOf('ensure_mirror_tag');
    expect(
      pushedIdx,
      isNonNegative,
      reason: 'TAG_PUSHED=1 niet in tag_and_push',
    );
    expect(
      mirrorIdx,
      isNonNegative,
      reason: 'ensure_mirror_tag niet aangeroepen in tag_and_push',
    );
    expect(
      pushedIdx,
      lessThan(mirrorIdx),
      reason:
          'TAG_PUSHED=1 moet vóór de mirror-stap staan, anders meldt de ERR-trap '
          'ten onrechte "niets naar buiten" als de mirror-push faalt.',
    );
  });

  // Lock voor de vroege macOS-ondertekencheck: een verdwenen notary-profiel
  // (v0.1.3-rc1) moet vóór de ~10 min build falen, niet pas bij het inzenden ná
  // de tag. preflight roept daarvoor notarize_macos.sh --preflight aan (verse run).
  test('preflight toetst de macOS-ondertekening vóór de build', () {
    expect(
      functionBody('preflight'),
      contains('notarize_macos.sh --preflight'),
      reason:
          'preflight moet "scripts/notarize_macos.sh --preflight" aanroepen zodat '
          'identiteit én notary-profiel vóór de build getoetst worden.',
    );
    expect(
      File('scripts/notarize_macos.sh').readAsStringSync(),
      contains('--preflight'),
      reason: 'notarize_macos.sh moet de --preflight-modus ondersteunen.',
    );
  });

  // Lock voor de fail-fast op een half-af gebleven release-branch: een verse run
  // hoort daar vroeg te stoppen met een --resume-advies, niet later te botsen op de
  // branch-push (non-fast-forward).
  test('een verse run stopt vroeg als de release-branch al op origin staat', () {
    expect(
      File(script).readAsStringSync(),
      contains(
        r'[ -z "$RESUME_TAG" ] && git ls-remote --exit-code origin "refs/heads/$BRANCH"',
      ),
      reason:
          'verwacht een verse-run-guard die op een bestaande release-branch vroeg '
          'faalt en naar --resume verwijst.',
    );
  });

  // --status vX.Y.Z: read-only overzicht. De tag is verplicht (zoals bij --resume);
  // deze weigering is hermetisch — vóór git/netwerk.
  test('--status zonder tag weigert', () {
    final r = Process.runSync('bash', [script, '--status']);
    expect(r.exitCode, isNot(0));
    expect(r.stderr.toString(), contains('tag'));
  }, skip: skipOnWindows);

  // Lock: --status is read-only. Het rapporteert en stopt (cmd_status; exit 0) vóór
  // de wachtwoordprompt en de pre-flight — het mag nooit iets muteren of om het
  // minisign-wachtwoord vragen. Statisch: leest het script.
  test('--status rapporteert en stopt vóór het wachtwoord', () {
    final src = File(script).readAsStringSync();
    final dispatch = src.indexOf('cmd_status\n  exit 0');
    final pw = src.indexOf('minisign-wachtwoord');
    expect(
      dispatch,
      isNonNegative,
      reason: 'verwacht een read-only --status-dispatch (cmd_status; exit 0).',
    );
    expect(pw, isNonNegative, reason: 'wachtwoordprompt niet gevonden.');
    expect(
      dispatch,
      lessThan(pw),
      reason: '--status moet stoppen vóór de wachtwoordprompt (read-only).',
    );
  });
}
