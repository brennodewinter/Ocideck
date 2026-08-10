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

  // Tag-veiligheid: de merge-commit moet de nieuwe versie dragen vóór we 'm taggen,
  // zodat een verkeerd merge_commit_sha nooit een willekeurige commit als deze
  // release tagt.
  test(
    'tag_and_push verifieert de versie van de merge-commit vóór het taggen',
    () {
      final body = functionBody('tag_and_push');
      final verifyIdx = body.indexOf(
        RegExp(r'git\s+show\b[^\n]*pubspec\.yaml'),
      );
      final annotateIdx = body.indexOf(
        RegExp(r'^\s*git\s+tag\s+-a\b', multiLine: true),
      );
      expect(
        verifyIdx,
        isNonNegative,
        reason:
            'tag_and_push moet de versie van de merge-commit '
            '(git show <sha>:pubspec.yaml) toetsen vóór het taggen.',
      );
      expect(annotateIdx, isNonNegative, reason: 'git tag -a niet gevonden.');
      expect(
        verifyIdx,
        lessThan(annotateIdx),
        reason:
            'de versiecontrole moet vóór "git tag -a" staan, anders tag je mogelijk '
            'de verkeerde commit.',
      );
    },
  );

  // Resume-netheid: de handtekening-upload moet idempotent zijn — een tweede
  // fase-3-poging (--resume) mag geen 409 of duplicaat geven.
  test(
    'de handtekening-upload verwijdert eerst een bestaande (idempotent)',
    () {
      final body = functionBody('phase3');
      final delIdx = body.indexOf(RegExp(r'api\s+DELETE[^\n]*assets'));
      final postIdx = body.indexOf(
        RegExp(r'api\s+POST[^\n]*assets\?name=SHA256SUMS\.minisig'),
      );
      expect(
        delIdx,
        isNonNegative,
        reason:
            'phase3 moet een bestaande SHA256SUMS.minisig eerst verwijderen '
            '(api DELETE …assets) zodat --resume geen 409/duplicaat geeft.',
      );
      expect(
        postIdx,
        isNonNegative,
        reason: 'de asset-upload (POST) niet gevonden.',
      );
      expect(
        delIdx,
        lessThan(postIdx),
        reason: 'de DELETE moet vóór de POST staan.',
      );
    },
  );

  // Robuustheid: alleen idempotente GET's worden herprobeerd, POST/DELETE nooit.
  test('api() herprobeert GET maar niet POST/DELETE', () {
    final body = functionBody('api');
    expect(
      body,
      contains(r'[ "$method" = "GET" ]'),
      reason:
          'api() moet alleen GET herproberen (niet POST/DELETE, die muteren).',
    );
    expect(
      body,
      contains(r'seq 1 "$tries"'),
      reason: 'api() moet een herprobeer-lus over \$tries hebben.',
    );
  });

  // #8: verschijnt SHA256SUMS niet (publiceren faalde), dan dispatcht fase 3 de
  // release-CI éénmalig opnieuw vóór het escaleren — geen directe dood meer.
  test(
    'fase 3 dispatcht de release-CI opnieuw als SHA256SUMS ontbreekt (#8)',
    () {
      final body = functionBody('phase3');
      final redispatchIdx = body.indexOf('workflows/release.yml/dispatches');
      final escalateIdx = body.indexOf('ook na een her-dispatch');
      expect(
        redispatchIdx,
        isNonNegative,
        reason:
            'fase 3 moet release.yml opnieuw dispatchen als SHA256SUMS ontbreekt, '
            'i.p.v. meteen te sterven.',
      );
      expect(
        escalateIdx,
        isNonNegative,
        reason: 'verwacht een escalatie-melding ná de her-dispatch.',
      );
      expect(
        redispatchIdx,
        lessThan(escalateIdx),
        reason: 'de her-dispatch moet vóór de escalatie staan.',
      );
    },
  );

  // Regressie: de notary-pre-flight gebruikte 'notarytool history --limit 1', maar
  // notarytool kent geen --limit (exit 64 = usage error) — daardoor blokkeerde de
  // pre-flight élke release met een vals "profiel verdwenen". Borg dat de
  // history-aanroep die vlag niet terugkrijgt. (Een runtime-rooktest kan niet in CI:
  // die heeft geen macOS-notary-credentials; daarom deze statische borg.)
  test('de notary-pre-flight gebruikt geen ongeldige notarytool-vlag', () {
    final src = File('scripts/notarize_macos.sh').readAsStringSync();
    final historyLine = src
        .split('\n')
        .firstWhere((l) => l.contains('notarytool history'), orElse: () => '');
    expect(
      historyLine,
      isNotEmpty,
      reason: 'notarytool history-aanroep niet gevonden in notarize_macos.sh.',
    );
    expect(
      historyLine.contains('--limit'),
      isFalse,
      reason:
          "'notarytool history' kent geen --limit; die vlag liet de pre-flight met "
          'exit 64 elke release blokkeren.',
    );
  });

  // Regressie voor het v0.4.2-incident: een afgebroken fase 1 mag de werkboom van
  // main niet vervuilen. De versiebump (pubspec, kOciDeckVersion, CHANGELOG, SBOM)
  // wordt op de release-branch GECOMMIT vóór 'make check-release' draait. Zo haalt de
  // opruimroute (cleanup_branch → 'git branch -D') een afgebroken run VOLLEDIG weg.
  // Bleef de bump een niet-gecommitte werkboom-edit, dan droeg de 'git checkout -' in
  // cleanup_branch 'm mee naar main (dirty tree), waarna de volgende verse run op de
  // versie-consistentiegate strandde ("pubspec staat op X maar origin/main op Y").
  test('de versiebump wordt gecommit vóór make check-release', () {
    final src = File(script).readAsStringSync();

    // Exact één staging van de vier versiedragende paden. Een tweede (bv. per ongeluk
    // ook nog in fase 2) zou daar op een lege 'git commit' vallen en de run afbreken.
    final addMatches = RegExp(
      r'git\s+add\s+pubspec\.yaml\s+lib/services/export_metadata\.dart\s+'
      r'sbom/\s+CHANGELOG\.md',
    ).allMatches(src).toList();
    expect(
      addMatches.length,
      1,
      reason:
          'verwacht precies één release-commit-staging (git add pubspec.yaml '
          'lib/services/export_metadata.dart sbom/ CHANGELOG.md).',
    );

    final commitIdx = src.indexOf(
      RegExp(r'git\s+commit[^\n]*chore\(release\): versie'),
    );
    final checkIdx = src.indexOf(
      RegExp(r'^make check-release\s*$', multiLine: true),
    );
    expect(
      commitIdx,
      isNonNegative,
      reason: 'de release-commit (chore(release): versie …) niet gevonden.',
    );
    expect(
      checkIdx,
      isNonNegative,
      reason: 'de kale "make check-release"-aanroep niet gevonden.',
    );
    expect(
      addMatches.first.start,
      lessThan(commitIdx),
      reason: 'de staging (git add) moet vóór de commit staan.',
    );
    expect(
      commitIdx,
      lessThan(checkIdx),
      reason:
          'de versiebump moet vóór make check-release gecommit worden, zodat een '
          'afgebroken fase 1 met "git branch -D" volledig opruimt en main schoon '
          'blijft (v0.4.2-incident).',
    );
  });

  // De poort mag niet in 'if ! make check-release; then die' zitten: die() doet
  // 'exit 1', en dat slaat de ERR-trap (en dus cleanup_branch) over — dan bleef een
  // afgebroken, half-gebumpte release-branch achter. Een kale aanroep valt via
  // set -e in on_err, dat wél opruimt. (Empirisch geverifieerd: 'exit 1' triggert de
  // ERR-trap niet; een bare command-fout wel.)
  test('make check-release valt in de ERR-opruiming, niet in een die-bypass', () {
    final src = File(script).readAsStringSync();
    expect(
      src.contains(RegExp(r'if\s*!\s*make check-release')),
      isFalse,
      reason:
          "make check-release mag niet in 'if ! … then die' staan: die() slaat via "
          'exit 1 de ERR-trap (cleanup_branch) over, waardoor een afgebroken '
          'release-branch met de versiebump zou blijven staan.',
    );
    expect(
      src.contains(RegExp(r'^make check-release\s*$', multiLine: true)),
      isTrue,
      reason:
          'verwacht een kale "make check-release" die bij falen via set -e in '
          'on_err (cleanup_branch) valt.',
    );
  });

  // De abort-route zelf: on_err ruimt vóór de tag-push de branch op, en
  // cleanup_branch verwijdert 'm met 'git branch -D'. Samen met de vervroegde commit
  // haalt dat een afgebroken run volledig weg zonder main te raken. De revert is
  // GERICHT (branch weg), nooit een blanket 'git reset --hard' — die zou het
  // ongecommitte werk van parallelle sessies op deze gedeelde checkout wissen.
  test('de pre-tag abort-route ruimt de release-branch op (geen reset --hard)', () {
    final onErr = functionBody('on_err');
    expect(
      onErr,
      contains('cleanup_branch'),
      reason:
          'on_err moet cleanup_branch aanroepen zolang de tag nog niet gepusht is '
          '(TAG_PUSHED=0).',
    );
    final cleanup = functionBody('cleanup_branch');
    expect(
      cleanup,
      matches(RegExp(r'git\s+branch\s+-D\b')),
      reason:
          'cleanup_branch moet de release-branch verwijderen (git branch -D); met '
          'de vervroegde commit haalt dat de versiebump volledig weg.',
    );
    expect(
      File(script).readAsStringSync().contains(RegExp(r'git\s+reset\s+--hard')),
      isFalse,
      reason:
          'geen blanket "git reset --hard": deze checkout wordt gedeeld door '
          'parallelle sessies; een reset zou hun ongecommitte werk wissen.',
    );
  });
}
