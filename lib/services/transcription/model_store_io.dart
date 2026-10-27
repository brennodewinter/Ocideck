import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/log.dart';
import 'model_download.dart';
import 'model_store.dart';
import 'whisper_model.dart';

/// De desktopmodelopslag (§4.4). De map ligt onder de app-support-directory
/// — per gebruiker, per app, buiten elke deck. We weigeren symbolische
/// koppelingen: iemand die in de modelmap een link legt, kan de engine een
/// willekeurig bestand laten laden, en dat is precies de aanval waarom de
/// containment-poort bestaat.
class IoModelStore implements TranscriptionModelStore {
  IoModelStore({Directory? root, List<Directory>? candidateRoots})
    : _rootOverride = root,
      _candidateRootsOverride = candidateRoots;

  final Directory? _rootOverride;

  /// Overschrijfbare kandidaatlijst voor tests — de echte productie-lijst
  /// komt uit [_candidateRoots] en hangt van de machine af. Zonder deze
  /// parameter zou een test gouden plaatjes en spiegels laten afhangen van
  /// wat er toevallig in `~/Downloads` van de bouwer ligt.
  final List<Directory>? _candidateRootsOverride;

  /// De hash leest gestreamd — een model van 1,5 GB mag niet eerst heel
  /// het geheugen in.
  static Future<String> _sha256Of(File file) =>
      sha256.bind(file.openRead()).single.then((d) => d.toString());

  @override
  Future<ModelStorePath> directory() async {
    final dir = _rootOverride ?? await _defaultRoot();
    if (!await dir.exists()) await dir.create(recursive: true);
    await _assertSafeDir(dir);
    return ModelStorePath(dir.path, p.isAbsolute(dir.path));
  }

  @override
  Future<ModelStorePath> modelPath(WhisperModel model) async {
    final dir = await directory();
    final file = File(p.join(dir.path, model.fileName));
    // Containment is hier een harde grens: `fileName` komt vandaag uit een
    // const catalogus, maar de dag dat hij uit een configuratie komt moet
    // dit de plek zijn die `../../` niet doorlaat.
    if (!p.isWithin(dir.path, file.path)) {
      throw StateError('modelpad ontsnapt uit de modelmap: ${model.fileName}');
    }
    return ModelStorePath(file.path, true);
  }

  @override
  Future<ModelInstallState> stateOf(WhisperModel model) async {
    final file = File((await modelPath(model)).path);
    if (await FileSystemEntity.isLink(file.path)) {
      logWarning(
        'ModelStore: ${model.fileName} is een koppeling — telt als afwezig',
      );
      return ModelInstallState.absent;
    }
    if (!await file.exists()) return ModelInstallState.absent;
    if (await file.length() != model.diskBytes) {
      // Een bestand met een andere omvang is een rest, geen model. We
      // verwijderen het niet stil — `delete` is de expliciete weg — maar
      // het mag ook niet als geïnstalleerd meetellen.
      return ModelInstallState.absent;
    }
    return ModelInstallState.present;
  }

  @override
  Future<bool> verify(WhisperModel model) async {
    if (await stateOf(model) != ModelInstallState.present) return false;
    final file = File((await modelPath(model)).path);
    final digest = await _sha256Of(file);
    return digest == model.sha256;
  }

  @override
  Future<void> delete(WhisperModel model) async {
    final file = File((await modelPath(model)).path);
    // Eerst de koppelingsvraag: `File.delete` volgt geen symlinks voor het
    // doel maar verwijdert de link zelf — precies goed. Alleen de `.part`
    // van hetzelfde model ruimen we meteen mee op.
    for (final path in [file.path, '${file.path}.part']) {
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type != FileSystemEntityType.notFound) {
        await File(path).delete();
      }
    }
  }

  @override
  Future<void> sweepPartials() async {
    final dir = Directory((await directory()).path);
    await for (final entry in dir.list(followLinks: false)) {
      if (entry.path.endsWith('.part')) {
        await entry.delete();
      }
    }
  }

  @override
  Future<List<ModelStorePath>> externalCandidates(WhisperModel model) async {
    final modelDir = (await directory()).path;
    final found = <ModelStorePath>[];
    for (final root in await _candidateRoots()) {
      try {
        await for (final entry in root.list(followLinks: false)) {
          // `type` volgt koppelingen bewust: in de huggingface-cache zijn
          // de bestandsnamen zelf links naar `blobs/`, en alleen het
          // einddoel vertelt of het echt een bestand is.
          if (await FileSystemEntity.type(entry.path) !=
              FileSystemEntityType.file) {
            continue;
          }
          if (p.isWithin(modelDir, entry.path)) continue;
          // Naam + omvang is het filter: een "ggml-small (1).bin" na een
          // dubbele download telt mee, een willekeurig bestand van 500 MB
          // niet. Dat het écht het catalogusmodel is, bewijst pas de
          // hash bij `adopt`.
          final name = p.basename(entry.path).toLowerCase();
          if (!name.startsWith('ggml') || !name.endsWith('.bin')) continue;
          if (await File(entry.path).length() != model.diskBytes) continue;
          found.add(ModelStorePath(entry.path, true));
        }
      } on FileSystemException catch (e) {
        // Een ontbrekende of geweigerde plek is geen kandidaat én geen
        // fout: op macOS kan de systeemvraag om maptoegang afgewezen
        // zijn — dan zwijgt de scan net zo goed als bij "niets gevonden".
        logWarning('ModelStore: kandidaatplek ${root.path} niet leesbaar', e);
      }
    }
    return found;
  }

  @override
  Future<ModelStorePath> adopt(
    WhisperModel model,
    ModelStorePath source,
  ) async {
    final src = File(source.path);
    final dest = await modelPath(model);
    if (!await src.exists()) {
      throw const ModelDownloadException(
        ModelDownloadFailure.ioFailed,
        'het gevonden bestand is verdwenen',
      );
    }
    // De hash beslist vóórdat er iets in de modelmap landt: een bestand
    // dat alleen qua naam en omvang "leek" wordt geweigerd, niet
    // opgeschoond en niet geïnstalleerd.
    if (await _sha256Of(src) != model.sha256) {
      throw ModelDownloadException(
        ModelDownloadFailure.invalidHash,
        '${source.path} is niet het ${model.id}-model uit de catalogus',
      );
    }
    final part = File('${dest.path}.part');
    try {
      // Kan alleen een rest zijn: `stateOf` telde `absent`, dus ligt er
      // of niets, of iets met de verkeerde omvang dat toch niet meetelt.
      final existing = File(dest.path);
      if (await existing.exists()) await existing.delete();
      await src.copy(part.path);
      await part.rename(dest.path);
    } on FileSystemException catch (e) {
      try {
        await part.delete();
      } on Object {
        // Opruimhulp is geen reden om de echte fout te verliezen.
      }
      throw ModelDownloadException(ModelDownloadFailure.ioFailed, e.message);
    }
    return dest;
  }

  /// De vaste lijst plekken waar een eerder zelf opgehaald
  /// whisper.cpp-model meestal ligt (#2601). Bewust kort en
  /// deterministisch — passief één map diep lezen, geen recursieve
  /// schijfscan en geen raden naar gebruikersmappen:
  ///
  ///  * `~/Downloads` — waar een handmatige download landt;
  ///  * `~/whisper.cpp/models` — de gangbare plek van een repocheckout;
  ///  * de datamap van pywhispercpp (de Python-binding downloadt dezelfde
  ///    `ggml`-bestanden per platformdirs-conventie);
  ///  * de huggingface-hubcache van de gepinde modelrepository —
  ///    `…/models--ggerganov--whisper.cpp/snapshots/<commit>/` opgelost tot
  ///    zijn submappen. `HF_HUB_CACHE` en `HF_HOME` overrulen de
  ///    standaardplek, net als bij de officiële client.
  Future<List<Directory>> _candidateRoots() async {
    final override = _candidateRootsOverride;
    if (override != null) return override;
    final env = Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'];
    if (home == null) return const [];
    final roots = <Directory>[
      Directory(p.join(home, 'Downloads')),
      Directory(p.join(home, 'whisper.cpp', 'models')),
      _pyWhisperCppDir(home, env),
    ];
    for (final hub in _hfHubDirs(home, env)) {
      final snapshots = Directory(
        p.join(hub.path, 'models--ggerganov--whisper.cpp', 'snapshots'),
      );
      try {
        await for (final entry in snapshots.list()) {
          if (entry is Directory) roots.add(entry);
        }
      } on FileSystemException catch (e) {
        logWarning('ModelStore: HF-cache ${snapshots.path} niet leesbaar', e);
      }
    }
    return roots;
  }

  /// De platformdirs-plek waar pywhispercpp zijn `ggml`-modellen parkeert.
  static Directory _pyWhisperCppDir(String home, Map<String, String> env) {
    if (Platform.isMacOS) {
      return Directory(
        p.join(home, 'Library', 'Application Support', 'pywhispercpp'),
      );
    }
    if (Platform.isWindows) {
      return Directory(p.join(env['LOCALAPPDATA'] ?? home, 'pywhispercpp'));
    }
    return Directory(
      p.join(
        env['XDG_DATA_HOME'] ?? p.join(home, '.local', 'share'),
        'pywhispercpp',
      ),
    );
  }

  /// De hub-cachemappen van huggingface-cli: expliciete omgevings-
  /// variabelen eerst, dan de standaard `~/.cache/huggingface/hub` die ook
  /// op Windows en macOS geldt.
  static List<Directory> _hfHubDirs(String home, Map<String, String> env) {
    final dirs = <Directory>[];
    final hubCache = env['HF_HUB_CACHE'];
    if (hubCache != null && hubCache.isNotEmpty) {
      dirs.add(Directory(hubCache));
    }
    final hfHome = env['HF_HOME'];
    if (hfHome != null && hfHome.isNotEmpty) {
      dirs.add(Directory(p.join(hfHome, 'hub')));
    }
    dirs.add(Directory(p.join(home, '.cache', 'huggingface', 'hub')));
    return dirs;
  }

  /// De modelmap, met dezelfde terugval als de git-zandbak: een
  /// `mkdtemp`-map met onradelijke naam in plaats van een vaste naam op
  /// gedeelde grond (zie git_cli_io._defaultSandboxDir).
  static Future<Directory> _defaultRoot() async {
    try {
      final support = await getApplicationSupportDirectory();
      return Directory(p.join(support.path, 'transcription', 'models'));
    } on Object catch (e) {
      logWarning(
        'ModelStore: geen app-support-map, tijdelijke privémap als modelmap',
        e,
      );
      return Directory.systemTemp.createTemp('ocideck_models_');
    }
  }

  /// De modelmap moet een echte map van ons zijn: geen koppeling (die zou
  /// `isWithin` omzeilen) en — eenmaal gevuld — geen vreemde bestanden die
  /// we niet kennen verwijderen we wél niet zelf (dat is opslag, geen
  /// aanvalsvector).
  static Future<void> _assertSafeDir(Directory dir) async {
    if (await FileSystemEntity.isLink(dir.path)) {
      throw StateError(
        'de modelmap is een symbolische koppeling en wordt niet vertrouwd: '
        '${dir.path}',
      );
    }
  }
}

TranscriptionModelStore createModelStore() => IoModelStore();
