/// De native-git-laag (§8.2, §10.2). Web-veilig: dit bestand raakt `dart:io`
/// niet aan, zodat het op elk platform geïmporteerd mag worden. De echte
/// subprocess-uitvoering zit in `git_cli_io.dart` — het enige bestand in de boom
/// dat een proces mag starten — en `git_cli_web.dart` is een eerlijke stub.
///
/// Alles wat een `git`-proces start, loopt via [GitCli]. De hardening van §10.2
/// (argv nooit een shell, gebruikersdata als operand achter `--end-of-options`,
/// het token nooit in argv/URL/config maar via de omgeving, een dichte omgeving,
/// geen hooks, tijdslimiet en begrensde uitvoer) hoort bij de implementatie,
/// niet bij de aanroeper. Zo is er één plek om te controleren.
library;

/// De uitkomst van één git-aanroep.
class GitResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const GitResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  bool get ok => exitCode == 0;
}

/// De semantische versie van de gevonden `git`, plus de ruwe regel voor logging.
class GitVersion implements Comparable<GitVersion> {
  final int major;
  final int minor;
  final int patch;
  final String raw;

  const GitVersion(this.major, this.minor, this.patch, {this.raw = ''});

  /// Leest `git version 2.54.0` (en varianten als `2.39.3 (Apple Git-146)`).
  /// Null wanneer er geen `x.y[.z]` in zit.
  static GitVersion? parse(String output) {
    final match = RegExp(r'(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(output);
    if (match == null) return null;
    return GitVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3) ?? '0'),
      raw: output.trim(),
    );
  }

  @override
  int compareTo(GitVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator >=(GitVersion other) => compareTo(other) >= 0;

  String get display => '$major.$minor.$patch';

  @override
  String toString() => display;
}

/// De ondergrens (§8.2/D5/D8): `--filter=blob:none` — de partiële clone waar de
/// hele native aanpak op leunt — vereist git ≥ 2.19. Daaronder wordt het native
/// plane in zijn geheel geweigerd, nooit functie voor functie.
const GitVersion kMinGitVersion = GitVersion(2, 19, 0);

/// Een config-sleutel/waarde die als `-c key=value` zou kunnen, maar via de
/// omgeving (`GIT_CONFIG_*`) wordt aangeleverd wanneer de waarde geheim is.
/// Zo belandt een token nooit in argv (wereldleesbaar via `ps`) of in
/// `.git/config` (§10.2).
class GitConfigOverride {
  final String key;
  final String value;
  final bool secret;

  const GitConfigOverride(this.key, this.value, {this.secret = false});
}

/// Een git-aanroep die faalde: een niet-nul exitcode, een tijdslimiet, of een
/// operand die de veiligheidsregels overtrad.
class GitCliException implements Exception {
  final String message;

  /// De exitcode, of null bij een tijdslimiet/validatiefout vóór het starten.
  final int? exitCode;

  /// Begrensde stderr, voor de melding. Nooit de argv (daar kan een operand in
  /// zitten) en nooit de omgeving (daar zit het token in).
  final String stderr;

  const GitCliException(this.message, {this.exitCode, this.stderr = ''});

  @override
  String toString() => 'GitCliException($message)';
}

/// De gehardde git-uitvoerder (§10.2). Eén implementatie per platform; op web is
/// het een stub die [isSupported] `false` meldt en bij gebruik gooit.
abstract class GitCli {
  /// Of dit platform überhaupt een `git`-proces kan starten (false op web).
  /// Een goedkope, synchrone voorcontrole vóór de echte [probe].
  bool get isSupported;

  /// Detecteer bruikbaar native git: op macOS eerst de Xcode-tools-controle
  /// (zodat de `/usr/bin/git`-shim geen installatiedialoog opent, §8.4), dan
  /// `git --version`. Geeft de versie terug, of null wanneer git ontbreekt, te
  /// oud is (< [kMinGitVersion]) of het platform het niet ondersteunt.
  Future<GitVersion?> probe();

  /// Voer één git-subcommando uit onder [workingDirectory].
  ///
  /// [args] zijn door OciDeck opgestelde, vertrouwde vlaggen (bv.
  /// `['clone', '--filter=blob:none']`). [operands] is onvertrouwde data
  /// (branch, pad, boodschap, herkomst): elke waarde wordt gevalideerd (mag niet
  /// met `-` beginnen) en achter `--end-of-options` gezet, zodat een repo geen
  /// vlaggen kan smokkelen. [config] gaat via de omgeving mee; een geheime
  /// waarde (het token) komt zo nooit in argv terecht.
  ///
  /// Gooit [GitCliException] bij een niet-nul exit, een tijdslimiet of een
  /// ongeldige operand.
  Future<GitResult> run(
    List<String> args, {
    List<String> operands,
    required String workingDirectory,
    List<GitConfigOverride> config,
    Duration timeout,
  });
}
