import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'git_cli.dart';

/// De echte uitvoerder: één subproces, gestart en afgeschermd. Vervangbaar in
/// tests zodat de argv/omgeving-opbouw te controleren is zonder echt te starten.
typedef ProcessRunner =
    Future<GitResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
      required Duration timeout,
    });

GitCli createGitCli() => NativeGitCli();

/// De gehardde git-uitvoerder op desktop (§10.2). Alle regels van §10.2 wonen
/// hier, en nergens anders in de boom start een proces.
class NativeGitCli implements GitCli {
  NativeGitCli({ProcessRunner? runner, Directory? sandboxDir})
    : _runner = runner ?? _spawn,
      _sandboxOverride = sandboxDir;

  final ProcessRunner _runner;
  final Directory? _sandboxOverride;
  Directory? _sandboxCache;

  static const Duration _probeTimeout = Duration(seconds: 10);

  /// Begrenst wat we van een git-proces in het geheugen trekken; een vijandige
  /// of losgeslagen `git` mag de app niet laten vollopen.
  static const int _maxOutputBytes = 8 * 1024 * 1024;

  @override
  bool get isSupported =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  Future<GitVersion?> probe() async {
    if (!isSupported) return null;

    // De macOS-val (§8.4): op een Mac zonder Xcode Command Line Tools is
    // `/usr/bin/git` een shim die géén fout geeft maar een installatiedialoog
    // opent. Dus eerst `xcode-select -p` (exit 0 = tools aanwezig) vóórdat we
    // git ook maar aanraken.
    if (Platform.isMacOS) {
      try {
        final xc = await _runner(
          'xcode-select',
          const ['-p'],
          environment: await _hardenedEnv(),
          timeout: _probeTimeout,
        );
        if (!xc.ok) return null;
      } on GitCliException {
        return null;
      }
    }

    try {
      final res = await _runner(
        'git',
        const ['--version'],
        environment: await _hardenedEnv(),
        timeout: _probeTimeout,
      );
      if (!res.ok) return null;
      final version = GitVersion.parse(res.stdout);
      if (version == null || !(version >= kMinGitVersion)) return null;
      return version;
    } on GitCliException {
      return null;
    }
  }

  @override
  Future<GitResult> run(
    List<String> args, {
    List<String> operands = const [],
    required String workingDirectory,
    List<GitConfigOverride> config = const [],
    Duration timeout = const Duration(seconds: 30),
  }) async {
    for (final operand in operands) {
      // Gebruikersdata is een operand, nooit een optie (§10.2): een waarde die
      // met `-` begint zou als vlag gelezen kunnen worden. Weiger vóór het
      // starten, zodat een repo geen `--upload-pack=…` kan smokkelen.
      if (operand.startsWith('-')) {
        throw GitCliException(
          'Operand mag niet met een streepje beginnen: $operand',
        );
      }
      if (operand.contains('\u0000') || operand.contains('\n')) {
        throw const GitCliException('Operand bevat een ongeldig teken');
      }
    }

    final sandbox = await _sandbox();
    final argv = <String>[
      // core.hooksPath naar een lege map: geen enkele hook draait, wat een
      // gekloonde repo ook meebrengt. Vóór het subcommando, want het is een
      // globale optie.
      '-c', 'core.hooksPath=${sandbox.path}',
      ...args,
      if (operands.isNotEmpty) '--end-of-options',
      ...operands,
    ];

    final result = await _runner(
      'git',
      argv,
      workingDirectory: workingDirectory,
      environment: await _hardenedEnv(config: config),
      timeout: timeout,
    );
    if (!result.ok) {
      throw GitCliException(
        'git ${args.isEmpty ? '' : args.first} faalde',
        exitCode: result.exitCode,
        stderr: _cap(result.stderr, 2000),
      );
    }
    return result;
  }

  /// Een dichte omgeving (§10.2): geen prompt die eeuwig kan blokkeren, geen
  /// systeem- of globale gitconfig die ons gedrag verandert, en het token via
  /// `GIT_CONFIG_*` in plaats van in argv of in `.git/config`.
  /// De variabelen die we uit de omgeving van de gebruiker overnemen. Alles wat
  /// hier niet in staat komt er niet in — zie [_hardenedEnv] voor waarom.
  ///
  /// Dit is bewust een toelatingslijst en geen verbodslijst: een verbodslijst
  /// veroudert zodra git een nieuwe `GIT_*` introduceert, en dan lekt het stil.
  ///
  /// `SSL_CERT_FILE`/`SSL_CERT_DIR` staan er bewust bij: op distributies die hun
  /// CA-bundel daarmee aanwijzen (NixOS, Alpine) breekt https zonder. Ze wijzen
  /// een CA-bundel aan, dus wie ze kan zetten kan de app een eigen CA laten
  /// vertrouwen — maar wie de omgeving van het proces kan zetten, kan sowieso
  /// meer. De kans dat ze wegvallen bij een échte gebruiker weegt zwaarder.
  /// `LANG`/`LC_ALL` staan hier bewust *niet* bij: die worden hieronder op `C`
  /// vastgezet. Zie [_hardenedEnv].
  static const _carriedPosix = {
    'PATH',
    'TMPDIR',
    'SSL_CERT_FILE',
    'SSL_CERT_DIR',
  };

  /// Windows heeft er meer nodig om überhaupt een proces te kunnen starten:
  /// zonder SystemRoot laden de socket-DLL's niet, en zonder PATHEXT vindt de
  /// loader `git.exe` niet.
  static const _carriedWindows = {
    'PATH',
    'PATHEXT',
    'SystemRoot',
    'SYSTEMROOT',
    'SystemDrive',
    'COMSPEC',
    'windir',
    'TEMP',
    'TMP',
    'USERPROFILE',
    'LOCALAPPDATA',
    'APPDATA',
    'ProgramData',
    'ProgramFiles',
    'ProgramFiles(x86)',
    'ProgramW6432',
  };

  /// De omgeving waarin `git` draait (§10.2) — volledig, want het proces start
  /// met `includeParentEnvironment: false`.
  ///
  /// Waarom volledig en niet "de omgeving van de gebruiker plus wat overrides":
  /// het token gaat als `http.extraHeader` mee, en dat is een
  /// `Authorization:`-header. Zou de omgeving van de gebruiker doorlekken, dan
  /// bepaalt zíjn omgeving of die header in een tracebestand belandt —
  /// `GIT_TRACE_CURL=1` samen met `GIT_TRACE_REDACT=0` schrijft hem onverkort
  /// weg. Datzelfde geldt voor de variabelen waarmee git een commando aanwijst
  /// dat het uitvoert (`GIT_ASKPASS`, `GIT_SSH_COMMAND`, `GIT_PROXY_COMMAND`,
  /// `GIT_EXTERNAL_DIFF`, …) en voor `GIT_CONFIG_PARAMETERS`, waarmee je
  /// willekeurige config injecteert. Geen daarvan hoort de app te kunnen
  /// overkomen doordat er iets in de schil stond.
  Future<Map<String, String>> _hardenedEnv({
    List<GitConfigOverride> config = const [],
  }) async {
    final sandbox = await _sandbox();
    final devNull = Platform.isWindows ? 'NUL' : '/dev/null';
    final carried = Platform.isWindows ? _carriedWindows : _carriedPosix;

    final env = <String, String>{
      // Alleen wat een proces nodig heeft om te kúnnen draaien.
      for (final entry in Platform.environment.entries)
        if (carried.contains(entry.key)) entry.key: entry.value,
      'GIT_TERMINAL_PROMPT': '0',
      'GIT_CONFIG_NOSYSTEM': '1',
      'GIT_CONFIG_GLOBAL': devNull,
      // Een gecontroleerde, lege HOME: geen `~/.gitconfig`, geen credential
      // cache, geen aliassen die code kunnen draaien.
      'HOME': sandbox.path,
      // Windows kijkt hiernaar in plaats van naar HOME.
      if (Platform.isWindows) 'USERPROFILE': sandbox.path,
      'GIT_ADVICE': '0',
      // Vangnet, voor het geval een header tóch ergens langs een trace komt: laat
      // git redigeren. Standaard doet hij dat al; dit zet het vast.
      'GIT_TRACE_REDACT': '1',
      // Git spreekt de taal van de schil. Wij lézen zijn uitvoer — of een push
      // werd afgewezen dan wel of we offline zijn, staat in zijn stderr — en
      // die twee betekenen iets heel anders voor het werk van de gebruiker.
      // Met een Nederlandse of Duitse git matchte "non-fast-forward" nergens
      // op, werd een afwijzing als "offline" geclassificeerd, en verdween het
      // werk stil in de wachtrij in plaats van een conflictmelding te geven.
      //
      // `LANGUAGE` staat erbij omdat gettext die vóór LC_ALL laat gaan; leeg
      // zetten is de enige manier om hem uit te schakelen.
      'LC_ALL': 'C',
      'LANGUAGE': '',
    };
    if (config.isNotEmpty) {
      env['GIT_CONFIG_COUNT'] = '${config.length}';
      for (var i = 0; i < config.length; i++) {
        env['GIT_CONFIG_KEY_$i'] = config[i].key;
        env['GIT_CONFIG_VALUE_$i'] = config[i].value;
      }
    }
    return env;
  }

  /// De lege, app-eigen map die als HOME én als hooks-map dient. Eén keer
  /// aangemaakt; in tests injecteerbaar.
  ///
  /// **Niet in de gedeelde tijdelijke ruimte.** Dit was
  /// `${Directory.systemTemp.path}/ocideck_git_sandbox`: een vaste, te raden
  /// naam in een map waar op een gedeelde Linux-machine iedereen mag schrijven.
  /// Wie daar vóór de eerste start een map neerzet met een `post-checkout`
  /// erin, krijgt die uitgevoerd zodra de gebruiker kloont — want deze map is
  /// óók `core.hooksPath`. De vorige versie nam een bestaande map zonder meer
  /// over, dus dat had niets in de weg gestaan.
  ///
  /// De app-support-map is per gebruiker en per app (`~/Library/Application
  /// Support` op macOS, `~/.local/share` op Linux, `%APPDATA%` op Windows). Een
  /// andere gebruiker komt er niet bij.
  ///
  /// [_assertSandboxSafe] blijft er als tweede slot omheen: dat het pad nu goed
  /// ligt, betekent niet dat wat er staat van ons is.
  Future<Directory> _sandbox() async {
    final cached = _sandboxCache;
    if (cached != null) return cached;
    final dir = _sandboxOverride ?? await _defaultSandboxDir();
    if (!await dir.exists()) await dir.create(recursive: true);
    await _assertSandboxSafe(dir);
    return _sandboxCache = dir;
  }

  /// De app-support-map, en anders een privé tijdelijke map.
  ///
  /// De terugval is géén stap terug naar het oude gedrag: `createTemp` maakt de
  /// map via `mkdtemp`, met een naam die niemand vooraf kan raden en — op POSIX
  /// — rechten 0700. Een andere gebruiker kan hem dus niet vóór ons aanmaken en
  /// er niet in schrijven. Wat het gat was, is de vaste náám op een plek waar
  /// iedereen mag schrijven; die is hier weg.
  ///
  /// De terugval bestaat omdat `getApplicationSupportDirectory` over een
  /// platformkanaal loopt en dus een geïnitialiseerde Flutter-binding vereist.
  /// In de app is die er altijd; op de kale Dart-VM van `flutter test` niet.
  static Future<Directory> _defaultSandboxDir() async {
    try {
      final support = await getApplicationSupportDirectory();
      return Directory(p.join(support.path, 'git_sandbox'));
    } catch (_) {
      return Directory.systemTemp.createTemp('ocideck_git_sandbox_');
    }
  }

  /// Zorg dat de zandbak is wat we denken: geen koppeling, en leeg.
  ///
  /// Allebei omdat de map als `core.hooksPath` dient. Een symbolische koppeling
  /// zou de hooks ergens ánders vandaan halen — daar valt niets veilig aan te
  /// repareren, dus dat is een weigering. Inhoud wordt wél opgeruimd in plaats
  /// van geweigerd: er hoort hier niets te staan, dus alles wat er staat is
  /// ofwel rommel ofwel een hook die iemand heeft neergelegd, en in beide
  /// gevallen is weghalen het goede antwoord. Weigeren zou git in het geheel
  /// onbruikbaar maken zodra er ooit één bestand belandt, en dat is een duurdere
  /// fout dan hij oplost.
  Future<void> _assertSandboxSafe(Directory dir) async {
    if (await FileSystemEntity.isLink(dir.path)) {
      throw GitCliException(
        'De git-zandbak is een symbolische koppeling en wordt niet vertrouwd: '
        '${dir.path}',
      );
    }
    await for (final entry in dir.list(followLinks: false)) {
      await entry.delete(recursive: true);
    }
  }

  static String _cap(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  /// De echte start: één proces, argv-array, geen shell, met een tijdslimiet die
  /// een vastgelopen `git` afschiet en met begrensde uitvoer.
  static Future<GitResult> _spawn(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    required Duration timeout,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      // Dít maakt de omgeving pas echt dicht. Standaard vult Dart hem aan met
      // die van het ouderproces, en dan bepaalt de schil van de gebruiker of een
      // GIT_TRACE_* het Authorization-header van ons token wegschrijft (§10.2,
      // OQ-10). [_hardenedEnv] levert alles wat git nodig heeft.
      includeParentEnvironment: false,
      runInShell: false,
    );
    final out = _CappedCollector(_maxOutputBytes);
    final err = _CappedCollector(_maxOutputBytes);
    final outDone = process.stdout.listen(out.add).asFuture<void>();
    final errDone = process.stderr.listen(err.add).asFuture<void>();

    var timedOut = false;
    final killer = Timer(timeout, () {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
    });

    final exitCode = await process.exitCode;
    killer.cancel();
    await Future.wait([outDone, errDone]);

    if (timedOut) {
      throw GitCliException(
        'git overschreed de tijdslimiet van ${timeout.inSeconds}s',
      );
    }
    return GitResult(exitCode: exitCode, stdout: out.text, stderr: err.text);
  }
}

/// Verzamelt bytes tot een cap; daarna gooit hij weg (maar telt door), zodat een
/// eindeloze stroom het geheugen niet vult.
class _CappedCollector {
  _CappedCollector(this.maxBytes);
  final int maxBytes;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  var _dropped = false;

  void add(List<int> chunk) {
    if (_dropped) return;
    if (_builder.length + chunk.length > maxBytes) {
      _builder.add(chunk.sublist(0, maxBytes - _builder.length));
      _dropped = true;
    } else {
      _builder.add(chunk);
    }
  }

  String get text => utf8.decode(_builder.toBytes(), allowMalformed: true);
}

@visibleForTesting
Future<GitResult> debugSpawn(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  Duration timeout = const Duration(seconds: 30),
}) => NativeGitCli._spawn(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  environment: environment,
  timeout: timeout,
);
