import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/git/git_cli.dart';
import 'package:ocideck/services/git/git_forge.dart';

// De stderr→foutsoort-classifier (§8.2/§10.2). Het native plane ving git's
// stderr wél op maar gooide het weg; dit zet die ruwe tekst om naar een
// bestaande [GitForgeError], zodat een clone/push-fout dezelfde begrijpelijke
// melding krijgt als de REST-weg in plaats van stil te verdwijnen.
//
// De classifier leunt op `LC_ALL=C` (git antwoordt in het Engels); dezelfde
// aanname als [isPushRejection], en door dezelfde poort in git_cli_test bewaakt.

GitForgeError _kindOf(String stderr) =>
    classifyGitCliError(GitCliException('git faalde', stderr: stderr)).kind;

void main() {
  group('classifyGitCliError', () {
    test('aanmeldfouten → auth', () {
      const gevallen = [
        "fatal: Authentication failed for 'https://git.example.org/x/y.git/'",
        'remote: HTTP Basic: Access denied\nfatal: Authentication failed',
        "fatal: could not read Username for 'https://git.example.org': "
            'terminal prompts disabled',
        'git@github.com: Permission denied (publickey).',
        'remote: Invalid username or password.',
      ];
      for (final s in gevallen) {
        expect(_kindOf(s), GitForgeError.auth, reason: s);
      }
    });

    test('geweigerd ondanks aanmelding → forbidden', () {
      const gevallen = [
        "fatal: unable to access 'https://git.example.org/x/y.git/': "
            'The requested URL returned error: 403',
        'remote: Forbidden\nfatal: unable to access',
        'remote: You are not allowed to push code to this project.',
        'remote: error: GH006: Protected branch update failed — read-only',
      ];
      for (final s in gevallen) {
        expect(_kindOf(s), GitForgeError.forbidden, reason: s);
      }
    });

    test('certificaatproblemen → tls', () {
      const gevallen = [
        "fatal: unable to access 'https://git.example.org/x.git/': "
            'SSL certificate problem: self-signed certificate',
        "fatal: unable to access 'https://git.example.org/x.git/': "
            'server certificate verification failed. CAfile: none',
      ];
      for (final s in gevallen) {
        expect(_kindOf(s), GitForgeError.tls, reason: s);
      }
    });

    test('naam lost niet op → unknownHost', () {
      const gevallen = [
        "fatal: unable to access 'https://git.example.org/x.git/': "
            'Could not resolve host: git.example.org',
        'ssh: Could not resolve hostname git.example.org: '
            'Name or service not known',
      ];
      for (final s in gevallen) {
        expect(_kindOf(s), GitForgeError.unknownHost, reason: s);
      }
    });

    test('repo of branch bestaat niet → notFound', () {
      const gevallen = [
        "remote: Repository not found.\nfatal: repository "
            "'https://git.example.org/x/weg.git/' not found",
        'fatal: Remote branch nietbestaand not found in upstream origin',
        "fatal: pathspec 'main' does not exist",
      ];
      for (final s in gevallen) {
        expect(_kindOf(s), GitForgeError.notFound, reason: s);
      }
    });

    test('verbinding weg/geweigerd → network', () {
      const gevallen = [
        "fatal: unable to access 'https://git.example.org/x.git/': "
            'Failed to connect to git.example.org port 443: Connection refused',
        "fatal: unable to access 'https://git.example.org/x.git/': "
            'Connection timed out after 30000 milliseconds',
      ];
      for (final s in gevallen) {
        expect(_kindOf(s), GitForgeError.network, reason: s);
      }
    });

    test('onbekende stderr valt terug op network (transient)', () {
      // Precies de offline file://-tak die native_git_mirror_test op
      // committedOffline toetst: geen van de specifieke zinnen matcht, dus de
      // terugval moet network zijn — anders wordt lokaal-bewaard-werk als een
      // onherstelbare fout gemeld in plaats van in de wachtrij gezet.
      final e = classifyGitCliError(
        const GitCliException(
          'git push faalde',
          stderr:
              "fatal: '/pad/origin.git' does not appear to be a git "
              'repository\nfatal: Could not read from remote repository.\n\n'
              'Please make sure you have the correct access rights\n'
              'and the repository exists.',
        ),
      );
      expect(e.kind, GitForgeError.network);
      expect(e.transient, isTrue);
      // "access rights"/"could not read from remote" mag géén auth/forbidden
      // triggeren — anders breekt de offline-durability-toets.
      expect(e.kind, isNot(GitForgeError.auth));
      expect(e.kind, isNot(GitForgeError.forbidden));
    });

    test('de specifieke reden wint van het generieke "unable to access"', () {
      // 403 en een certificaatprobleem dragen allebei óók "unable to access".
      // Wie dat generieke eerst zou vangen, schreef ze als "netwerk" weg.
      expect(
        _kindOf(
          "fatal: unable to access 'https://h/x.git/': "
          'The requested URL returned error: 403',
        ),
        GitForgeError.forbidden,
      );
      expect(
        _kindOf(
          "fatal: unable to access 'https://h/x.git/': "
          'SSL certificate problem: unable to get local issuer certificate',
        ),
        GitForgeError.tls,
      );
    });

    test('de ruwe git-boodschap reist mee voor het log', () {
      final e = classifyGitCliError(
        const GitCliException('git clone faalde', stderr: 'fatal: whatever'),
      );
      expect(e.message, 'git clone faalde');
    });
  });
}
