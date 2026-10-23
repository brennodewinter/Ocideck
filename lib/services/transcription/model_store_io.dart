import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/log.dart';
import 'model_store.dart';
import 'whisper_model.dart';

/// De desktopmodelopslag (§4.4). De map ligt onder de app-support-directory
/// — per gebruiker, per app, buiten elke deck. We weigeren symbolische
/// koppelingen: iemand die in de modelmap een link legt, kan de engine een
/// willekeurig bestand laten laden, en dat is precies de aanval waarom de
/// containment-poort bestaat.
class IoModelStore implements TranscriptionModelStore {
  IoModelStore({Directory? root}) : _rootOverride = root;

  final Directory? _rootOverride;

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
