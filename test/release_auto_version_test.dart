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

  // Regressie voor de v0.4.4-run van 15-08-2026. cleanup_branch deed zijn twee
  // git-commando's met '2>/dev/null || true'. Faalde de checkout (een werkboom die
  // één bestand draagt dat tussen de branches verschilt is genoeg), dan faalde
  // 'branch -D' gegarandeerd óók — de branch stond dan nog uitgecheckt — terwijl
  // het scherm zei dat er was opgeruimd. De release-branch mét versiebump bleef
  // staan, en de eerstvolgende 'git checkout -b' takte er ongemerkt van af: zo
  // kwam die bump terecht in een PR die een DAST-fix heette.
  test('een mislukte opruiming van de release-branch wordt gemeld, niet gesmoord', () {
    final cleanup = functionBody('cleanup_branch');
    for (final cmd in ['git checkout', 'git branch -D']) {
      final line = cleanup
          .split('\n')
          .firstWhere(
            (l) =>
                l.contains(RegExp(RegExp.escape(cmd))) &&
                !l.trimLeft().startsWith('#'),
            orElse: () => fail('$cmd niet gevonden in cleanup_branch'),
          );
      expect(
        line,
        isNot(contains('|| true')),
        reason:
            '"$cmd" in cleanup_branch mag niet met "|| true" worden weggemoffeld: '
            'dan blijft een release-branch mét versiebump staan terwijl de melding '
            'zegt dat hij is opgeruimd.',
      );
    }
    expect(
      cleanup,
      contains('cleanup_failed'),
      reason:
          'cleanup_branch moet een mislukte opruiming melden (cleanup_failed), '
          'zodat de gebruiker weet dat de branch met de versiebump er nog staat.',
    );
    expect(
      functionBody('cleanup_failed'),
      matches(RegExp(r'git\s+branch\s+-D')),
      reason:
          'de melding moet het herstelcommando meegeven; zonder dat blijft de '
          'gebruiker met een halve release-branch zitten.',
    );

    // En on_err mag de opruiming niet vooraf aankondigen als voldongen feit —
    // cleanup_branch meldt zelf wat er werkelijk gebeurde.
    expect(
      functionBody('on_err'),
      isNot(contains('wordt opgeruimd')),
      reason:
          'on_err beweerde "de release-branch wordt opgeruimd" vóórdat de '
          'opruiming had plaatsgevonden; die uitkomst hoort van cleanup_branch '
          'te komen.',
    );
  });

  // Tweede helft van diezelfde run: een 'flutter run' die in deze werkboom bleef
  // staan hield .dart_tool bezet. 'flutter clean' meldt dat wél maar eindigt met
  // exit 0, waarna de eerstvolgende 'dart run' viel over een half verdwenen
  // hooks_runner-cache — tien minuten en een wachtwoord verder, op een stap
  // (sbom-verify) die niets met de oorzaak te maken had.
  test('een bezette werkboom wordt getoetst vóór het wachtwoord', () {
    final src = File(script).readAsStringSync();
    final guardIdx = src.indexOf(
      RegExp(r'^assert_workspace_idle\s*$', multiLine: true),
    );
    final promptIdx = src.indexOf('minisign-wachtwoord');
    expect(
      guardIdx,
      isNonNegative,
      reason:
          'release_auto moet assert_workspace_idle aanroepen: een tweede '
          'flutter-proces in deze werkboom maakt de schone bouw onmogelijk.',
    );
    expect(
      guardIdx,
      lessThan(promptIdx),
      reason:
          'de toets hoort vóór de wachtwoordprompt: anders tikt de gebruiker '
          'een wachtwoord in voor een keten die tien minuten later alsnog valt.',
    );
  });

  test('notarize_macos toetst dat flutter clean écht schoonmaakte', () {
    const notarize = 'scripts/notarize_macos.sh';
    final src = File(notarize).readAsStringSync();
    final cleanIdx = src.indexOf(
      RegExp(r'^\s*flutter clean\s*$', multiLine: true),
    );
    final checkIdx = src.indexOf(
      RegExp(r'^\s*if \[\[ -d \.dart_tool \]\]', multiLine: true),
    );
    final buildIdx = src.indexOf(
      RegExp(r'^\s*make build-macos\s*$', multiLine: true),
    );
    expect(
      cleanIdx,
      isNonNegative,
      reason: 'geen "flutter clean" in $notarize',
    );
    expect(
      checkIdx,
      isNonNegative,
      reason:
          '"flutter clean" eindigt met exit 0 ook als het .dart_tool liet staan; '
          '$notarize moet die invariant zelf toetsen vóór het bouwt.',
    );
    expect(cleanIdx, lessThan(checkIdx));
    expect(
      checkIdx,
      lessThan(buildIdx),
      reason: 'de toets hoort vóór "make build-macos", niet erna.',
    );
  });

  // Gedragstoets, geen grep: speelt de opruiming na in een wegwerp-repo. De
  // statische toets hierboven pint de vórm; deze pint wat er werkelijk gebeurt —
  // en dat is wat op 15-08-2026 stilletjes misging.
  test('cleanup_branch ruimt op, of zegt eerlijk dat het niet lukte', () {
    final snippet =
        'cleanup_failed() {\n${functionBody('cleanup_failed')}\n}\n'
        'cleanup_branch() {\n${functionBody('cleanup_branch')}\n}\n';

    ({String out, bool branchLeft, String head}) play({
      required bool dirty,
      required String startBranch,
    }) {
      final dir = Directory.systemTemp.createTempSync('ocideck-cleanup');
      String git(List<String> args) {
        final r = Process.runSync('git', args, workingDirectory: dir.path);
        if (r.exitCode != 0) fail('git ${args.join(' ')}: ${r.stderr}');
        return (r.stdout as String).trim();
      }

      git(['-c', 'init.defaultBranch=main', 'init', '-q', '.']);
      git(['config', 'user.email', 'test@example.invalid']);
      git(['config', 'user.name', 'test']);
      git(['config', 'commit.gpgsign', 'false']);
      File('${dir.path}/f.txt').writeAsStringSync('een\n');
      git(['add', '.']);
      git(['commit', '-qm', 'basis']);
      // De release-branch met zijn versiebump, precies zoals fase 1 hem achterlaat.
      git(['checkout', '-q', '-B', 'rel', 'main']);
      File('${dir.path}/f.txt').writeAsStringSync('versiebump\n');
      git(['commit', '-qam', 'bump']);
      if (dirty) {
        File('${dir.path}/f.txt').writeAsStringSync('ongecommit werk\n');
      }
      File('${dir.path}/run.sh').writeAsStringSync(
        'set -Eeuo pipefail\n'
        'START_BRANCH=$startBranch\nBRANCH=rel\nCLEANUP_BACK=""\n'
        '$snippet\ncleanup_branch\n',
      );
      final r = Process.runSync('bash', [
        '${dir.path}/run.sh',
      ], workingDirectory: dir.path);
      final left =
          Process.runSync('git', [
            'rev-parse',
            '-q',
            '--verify',
            'refs/heads/rel',
          ], workingDirectory: dir.path).exitCode ==
          0;
      final head = git(['branch', '--show-current']);
      final out = '${r.stdout}${r.stderr}';
      dir.deleteSync(recursive: true);
      return (out: out, branchLeft: left, head: head);
    }

    final ok = play(dirty: false, startBranch: 'main');
    expect(ok.branchLeft, isFalse, reason: 'schone werkboom: branch hoort weg');
    expect(ok.head, 'main');
    expect(ok.out, contains('opgeruimd'));

    // De faalkant. Vroeger: beide git-fouten gesmoord, branch blijft staan, en
    // niets op het scherm — waarna de volgende 'checkout -b' de bump erfde.
    final blocked = play(dirty: true, startBranch: 'main');
    expect(
      blocked.branchLeft,
      isTrue,
      reason:
          'de checkout kan hier niet slagen; dat is de premisse van de toets',
    );
    expect(
      blocked.out,
      contains('NIET opgeruimd'),
      reason: 'een mislukte opruiming moet zichtbaar zijn, niet gesmoord',
    );
    expect(
      blocked.out,
      contains('git branch -D rel'),
      reason: 'de melding hoort het herstelcommando mee te geven',
    );

    // Nasleep van een eerdere gefaalde run: je stáát al op de release-branch.
    // Teruggaan naar jezelf zou 'branch -D' laten weigeren; val terug op main.
    final fromRel = play(dirty: false, startBranch: 'rel');
    expect(fromRel.branchLeft, isFalse);
    expect(fromRel.head, 'main');
  }, skip: skipOnWindows);

  // Gedragstoets in een wegwerp-repo, net als bij cleanup_branch hierboven: de
  // vórm van dit blok zegt niets, wat het achterlaat wel.
  //
  // De regel die het bewaakt: een verschoven momentopname (upstream bewoog, de
  // gegenereerde catalogus komt er woordelijk hetzelfde uit) is administratie en
  // rijdt vanzelf mee; een verschoven INHOUD stopt de keten. En in beide
  // faalgevallen blijft er niets ongecommit staan — zo'n rest reist met de
  // checkout van cleanup_branch mee naar main, en precies zo kwam de
  // v0.4.2-versiebump ooit op een vreemde branch terecht.
  test('een verschoven momentopname rijdt mee, verschoven inhoud niet', () {
    final snippet =
        'refresh_catalog_snapshot() {\n'
        '${functionBody('refresh_catalog_snapshot')}\n}\n';

    ({String out, int code, int commits, bool dirty}) play({
      required String stubBody,
      required int stubExit,
    }) {
      final dir = Directory.systemTemp.createTempSync('ocideck-catalogs');
      String git(List<String> args) {
        final r = Process.runSync('git', args, workingDirectory: dir.path);
        if (r.exitCode != 0) fail('git ${args.join(' ')}: ${r.stderr}');
        return (r.stdout as String).trim();
      }

      git(['-c', 'init.defaultBranch=main', 'init', '-q', '.']);
      git(['config', 'user.email', 'test@example.invalid']);
      git(['config', 'user.name', 'test']);
      git(['config', 'commit.gpgsign', 'false']);
      Directory('${dir.path}/lib/services').createSync(recursive: true);
      Directory('${dir.path}/docs').createSync(recursive: true);
      Directory('${dir.path}/scripts').createSync(recursive: true);
      File(
        '${dir.path}/lib/services/maswe_catalog.dart',
      ).writeAsStringSync("const masweSnapshotDate = '2026-08-04';\n");
      File(
        '${dir.path}/lib/services/maswe_catalog_data.dart',
      ).writeAsStringSync('// gegenereerd\n');
      File(
        '${dir.path}/docs/LICENSE_COMPLIANCE.md',
      ).writeAsStringSync('| snapshot **2026-08-04** |\n');
      git(['add', '.']);
      git(['commit', '-qm', 'basis']);

      File('${dir.path}/scripts/refresh_catalogs.sh').writeAsStringSync(
        '#!/usr/bin/env bash\nset -e\n$stubBody\nexit $stubExit\n',
      );
      Process.runSync('chmod', [
        '+x',
        '${dir.path}/scripts/refresh_catalogs.sh',
      ]);

      File('${dir.path}/run.sh').writeAsStringSync(
        'set -Eeuo pipefail\n'
        'STEP=""\nCATALOGS_STALE=maswe\n'
        'section() { printf "== %s ==\\n" "\$1"; }\n'
        'log() { printf "   %s\\n" "\$1"; }\n'
        'die() { printf "release-auto: %s\\n" "\$1" >&2; exit 1; }\n'
        // Geen netwerk in een test: de nacontrole krijgt een lege stand.
        'stale_catalog_ids() { :; }\n'
        'catalogs_probe_json() { printf "[]"; }\n'
        '$snippet\nrefresh_catalog_snapshot\n',
      );
      final r = Process.runSync('bash', [
        '${dir.path}/run.sh',
      ], workingDirectory: dir.path);
      final commits = int.parse(git(['rev-list', '--count', 'HEAD']));
      // Alleen de bestanden die deze stap aangaat: run.sh en het stub-script
      // staan als ongevolgde bestanden in dezelfde map en zeggen niets.
      final dirty = git([
        'status',
        '--porcelain',
        '--',
        'lib',
        'docs',
      ]).isNotEmpty;
      final out = '${r.stdout}${r.stderr}';
      dir.deleteSync(recursive: true);
      return (out: out, code: r.exitCode, commits: commits, dirty: dirty);
    }

    // Alleen boekhouding: de constante en de licentietabel schuiven op, het
    // gegenereerde deel niet. Dat hoort door te lopen, als eigen commit.
    final boekhouding = play(
      stubBody:
          "printf \"const masweSnapshotDate = '2026-09-01';\\n\" "
          '> lib/services/maswe_catalog.dart\n'
          'printf "| snapshot **2026-09-01** |\\n" > docs/LICENSE_COMPLIANCE.md',
      stubExit: 0,
    );
    expect(boekhouding.code, 0, reason: boekhouding.out);
    expect(boekhouding.commits, 2, reason: 'de verschuiving hoort vastgelegd');
    expect(boekhouding.dirty, isFalse);
    expect(boekhouding.out, contains('bundel zelf is niet veranderd'));

    // Inhoud verschoven: hier stopt het, en de werkboom blijft schoon achter.
    final inhoud = play(
      stubBody:
          "printf \"const masweSnapshotDate = '2026-09-01';\\n\" "
          '> lib/services/maswe_catalog.dart\n'
          'printf "// een zwakheid erbij\\n" >> '
          'lib/services/maswe_catalog_data.dart',
      stubExit: 0,
    );
    expect(inhoud.code, isNot(0));
    expect(inhoud.out, contains('INHOUD'));
    expect(inhoud.commits, 1, reason: 'niets vastgelegd');
    expect(
      inhoud.dirty,
      isFalse,
      reason: 'een rest zou met cleanup_branch meereizen naar main',
    );

    // De verversing zelf faalt halverwege: ook dan blijft er niets staan.
    final kapot = play(
      stubBody:
          "printf \"const masweSnapshotDate = 'half';\\n\" "
          '> lib/services/maswe_catalog.dart',
      stubExit: 3,
    );
    expect(kapot.code, isNot(0));
    expect(kapot.out, contains('faalde'));
    expect(kapot.commits, 1);
    expect(kapot.dirty, isFalse);

    // Niets veranderd terwijl de poort wél drift meldt: dat is geen groen licht.
    final stil = play(stubBody: ':', stubExit: 0);
    expect(stil.code, isNot(0));
    expect(stil.out, contains('geen enkele wijziging'));
  }, skip: skipOnWindows);

  test('de wachtwoordprompt meldt zich als eigen stap', () {
    // Een STEP-label blijft staan tot het volgende. Zonder eigen label kreeg een
    // fout bij de prompt (bijvoorbeeld read op EOF, zonder tty) de naam van de
    // vorige stap toegewezen — dezelfde verwarring als build-release/notarize.
    final src = File(script).readAsStringSync();
    final stepIdx = src.indexOf('STEP="wachtwoord"');
    final promptIdx = src.indexOf('minisign-wachtwoord');
    expect(
      stepIdx,
      isNonNegative,
      reason: 'de promptsectie hoort een eigen STEP te zetten.',
    );
    expect(stepIdx, lessThan(promptIdx));
  });

  test('bouwen en notariseren melden zich als aparte stap', () {
    // Onder één STEP-label meldde de ERR-trap "make build-release" terwijl het
    // notariseren viel; dat stuurt de diagnose naar de verkeerde stap.
    final src = File(script).readAsStringSync();
    final stepIdx = src.indexOf('STEP="make notarize-macos"');
    final callIdx = src.indexOf(
      RegExp(r'^make notarize-macos\s*$', multiLine: true),
    );
    expect(
      stepIdx,
      isNonNegative,
      reason: 'notarize-macos hoort een eigen STEP-label te hebben.',
    );
    expect(stepIdx, lessThan(callIdx));
  });
}
