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

import 'git_forge.dart';

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

/// Of een mislukte `git push` een *afwijzing* was — iemand anders is je voor
/// geweest — in plaats van een storing onderweg.
///
/// Het onderscheid bepaalt wat er met het werk van de gebruiker gebeurt: een
/// afwijzing hoort een conflictmelding te geven, een storing gaat de wachtrij
/// in om later vanzelf mee te gaan. Ze verwarren is duur, en het gebeurde: de
/// herkenning leest Engelse tekst, terwijl `git` de taal van de schil sprak.
/// Met een Nederlandse of Duitse git matchte niets, en werd elke afwijzing als
/// "offline" weggeschreven — het werk verdween stil in de wachtrij en de
/// gebruiker hoorde nooit dat er een conflict was.
///
/// Dat het nu wél mag: `GitCli` zet `LC_ALL=C` en leegt `LANGUAGE`, dus git
/// antwoordt altijd in het Engels. Zonder die vastzetting is deze functie niet
/// betrouwbaar en hoort ze niet gebruikt te worden.
///
/// Aparte, pure functie zodat de gevallen te testen zijn zonder een echte
/// remote te hoeven afwijzen.
bool isPushRejection(String stderr) {
  final lower = stderr.toLowerCase();
  // De drie zinnen waarmee git een geweigerde ref benoemt.
  if (lower.contains('non-fast-forward') ||
      lower.contains('fetch first') ||
      lower.contains('stale info')) {
    return true;
  }
  // Vangnet voor formuleringen die we niet bij naam kennen. "resolve" sluit de
  // gevallen uit waarin git juist over een merge-conflict in de werkkopie
  // praat; dat is geen push-afwijzing.
  return lower.contains('rejected') && !lower.contains('resolve');
}

/// Vertaal de stderr van een mislukte git-aanroep naar een [GitForgeException]
/// met een van de *bestaande* [GitForgeError]-soorten, zodat een native-git-fout
/// dezelfde begrijpelijke melding krijgt (`gitForgeErrorMessage`) als de
/// REST-weg — in plaats van als kale [GitCliException] stil in de top-level
/// `runZonedGuarded` te verdwijnen.
///
/// Net als [isPushRejection] leunt dit op de taal van git: `GitCli` zet
/// `LC_ALL=C` en leegt `LANGUAGE`, dus de Engelse zinnen hieronder matchen.
/// Zonder die vastzetting is deze functie niet betrouwbaar.
///
/// De volgorde is bewust van bijzonder naar algemeen. Git meldt de échte reden
/// (`403`, een certificaatprobleem, een naam die niet oploste) vaak sámen met
/// het generieke `unable to access '…'`. Wie dat generieke eerst zou vangen,
/// schreef elke fout als "netwerk" weg. De terugval is [GitForgeError.network]
/// (transient): een onbekende stderr is meestal een storing onderweg, en dat is
/// de soort die uitstel — de wachtrij — rechtvaardigt, niet een onherstelbare
/// melding.
///
/// De ruwe [GitCliException.message] reist als [GitForgeException.message] mee
/// voor het log; op het scherm komt `gitForgeErrorMessage(kind)`, niet die tekst.
GitForgeException classifyGitCliError(GitCliException e) {
  final s = e.stderr.toLowerCase();
  bool has(String needle) => s.contains(needle);

  // Aanmelden mislukt: het token deugt niet, of git kon er niet om vragen (de
  // prompt staat uit, §10.2).
  if (has('authentication failed') ||
      has('could not read username') ||
      has('could not read password') ||
      has('invalid username or password') ||
      has('permission denied (publickey)')) {
    return GitForgeException(GitForgeError.auth, e.message);
  }
  // Aangemeld, maar niet toegestaan: te weinig scope, alleen-lezen, of een
  // limiet. 403 hoort hier, nooit bij auth — een nieuw token helpt pas mét meer
  // rechten.
  if (has('403') ||
      has('forbidden') ||
      has('not allowed') ||
      has('read-only') ||
      has('read only')) {
    return GitForgeException(GitForgeError.forbidden, e.message);
  }
  // Certificaat niet vertrouwd — eigen soort, want de gebruiker kan het bekijken
  // en vertrouwen.
  if (has('ssl certificate problem') ||
      has('server certificate verification failed') ||
      has('certificate')) {
    return GitForgeException(GitForgeError.tls, e.message);
  }
  // Naam lost niet op: een tikfout — of (zie `_queueIfOffline`) domweg offline.
  if (has('could not resolve host') ||
      has('could not resolve hostname') ||
      has('name or service not known') ||
      has('name resolution')) {
    return GitForgeException(GitForgeError.unknownHost, e.message);
  }
  // De repo of branch bestaat niet — of het token mag hem niet zien.
  // "Remote branch <naam> not found" valt onder 'not found'.
  if (has('repository not found') ||
      has('not found') ||
      has('does not exist')) {
    return GitForgeException(GitForgeError.notFound, e.message);
  }
  // Verbinding weggevallen of geweigerd: uitstel, geen mislukking. `unable to
  // access` staat bewust als laatste — het staat óók in de specifiekere gevallen
  // hierboven, die vóórgaan.
  if (has('connection refused') ||
      has('connection timed out') ||
      has('failed to connect') ||
      has('could not connect') ||
      has('unable to access')) {
    return GitForgeException(GitForgeError.network, e.message, transient: true);
  }
  // Onbekende stderr: behandel als een voorbijgaande storing (zie de doc).
  return GitForgeException(GitForgeError.network, e.message, transient: true);
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
