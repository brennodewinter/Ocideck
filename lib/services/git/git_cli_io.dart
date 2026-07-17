import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/foundation.dart' show visibleForTesting;

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
  Future<Map<String, String>> _hardenedEnv({
    List<GitConfigOverride> config = const [],
  }) async {
    final sandbox = await _sandbox();
    final devNull = Platform.isWindows ? 'NUL' : '/dev/null';
    final env = <String, String>{
      'GIT_TERMINAL_PROMPT': '0',
      'GIT_CONFIG_NOSYSTEM': '1',
      'GIT_CONFIG_GLOBAL': devNull,
      // Een gecontroleerde, lege HOME: geen `~/.gitconfig`, geen credential
      // cache, geen aliassen die code kunnen draaien.
      'HOME': sandbox.path,
      'GIT_ADVICE': '0',
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
  Future<Directory> _sandbox() async {
    final cached = _sandboxCache;
    if (cached != null) return cached;
    final dir =
        _sandboxOverride ??
        Directory('${Directory.systemTemp.path}/ocideck_git_sandbox');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _sandboxCache = dir;
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
