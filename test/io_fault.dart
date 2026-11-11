// Foutinjectie voor `dart:io` in tests: laat één gekozen bestandsoperatie op
// één gekozen pad falen, terwijl al het andere de echte schijf raakt.
//
// Aanleiding: het openpad las zijn grensgevallen alleen via ontbrekende
// bestanden — dat toetst de `exists()==false`-tak, niet de uitzonderingen die
// een stat of lees ook kan gooien (weg tussen twee acties, geweigerde toegang,
// verdwenen volume). Vijf issues uit één incident (#2875-#2879) waren precies
// zo'n onbeschermde stap. Dit harnas maakt het goedkoop om per ingang te eisen:
// een filesystemfout is een teruggegeven uitkomst, nooit een weggegooide
// uitzondering.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Draait [body] terwijl de operaties in [failOn] op het bestand op
/// [targetPath] [error] gooien; alle andere bestanden en operaties gaan naar
/// de echte implementatie. Gebruik de realpath als doel wanneer de code onder
/// test `resolveSymbolicLinks` uitvoert (macOS symlinkt /var → /private/var).
///
/// Namen voor [failOn] zijn de methode-namen op [File]: `exists`,
/// `existsSync`, `length`, `readAsBytes`, `readAsString`, `openRead`, `stat`.
/// Gooit [body] zelf ook maar iets, dan komt dat er gewoon uit — precies wat
/// een test wil zien.
Future<T> runWithFileFault<T>(
  Future<T> Function() body, {
  required String targetPath,
  required Set<String> failOn,
  Object error = const FileSystemException('geïnjecteerde testfout'),
}) {
  final target = p.normalize(targetPath);
  final parent = IOOverrides.current;
  return IOOverrides.runZoned(
    body,
    createFile: (path) {
      // `File(path)` hier zou dezezelfde override weer aanroepen; de
      // passthrough laat `IOOverrides.current` naar de echte
      // basisimplementatie wijzen zodat een echt bestand ontstaat.
      final real = parent != null
          ? parent.createFile(path)
          : IOOverrides.runWithIOOverrides(() => File(path), _RealIO());
      return p.normalize(path) == target
          ? _FaultFile(real, failOn, error)
          : real;
    },
    createDirectory: (path) {
      final real = parent != null
          ? parent.createDirectory(path)
          : IOOverrides.runWithIOOverrides(() => Directory(path), _RealIO());
      return p.normalize(path) == target
          ? _FaultDirectory(real, failOn, error)
          : real;
    },
  );
}

/// Lege [IOOverrides]: de basisimplementaties draaien op echte `dart:io`.
final class _RealIO extends IOOverrides {}

/// Een [File] die naar [_delegate] doorspeelt, behalve de leden in [_failOn].
/// Alleen de leden die de code onder test raakt zijn overschreven; de rest
/// sterft luid in [noSuchMethod] in plaats van stil een ander resultaat te
/// veinzen.
class _FaultFile implements File {
  _FaultFile(this._delegate, this._failOn, this._error);

  final File _delegate;
  final Set<String> _failOn;
  final Object _error;

  void _maybeThrow(String member) {
    if (_failOn.contains(member)) throw _error;
  }

  @override
  String get path => _delegate.path;

  @override
  Future<bool> exists() {
    _maybeThrow('exists');
    return _delegate.exists();
  }

  @override
  bool existsSync() {
    _maybeThrow('existsSync');
    return _delegate.existsSync();
  }

  @override
  Future<int> length() {
    _maybeThrow('length');
    return _delegate.length();
  }

  @override
  Future<Uint8List> readAsBytes() {
    _maybeThrow('readAsBytes');
    return _delegate.readAsBytes();
  }

  @override
  Future<String> readAsString({Encoding encoding = utf8}) {
    _maybeThrow('readAsString');
    return _delegate.readAsString(encoding: encoding);
  }

  @override
  Stream<List<int>> openRead([int? start, int? end]) {
    _maybeThrow('openRead');
    return _delegate.openRead(start, end);
  }

  @override
  Future<FileStat> stat() {
    _maybeThrow('stat');
    return _delegate.stat();
  }

  @override
  String resolveSymbolicLinksSync() => _delegate.resolveSymbolicLinksSync();

  @override
  Future<String> resolveSymbolicLinks() => _delegate.resolveSymbolicLinks();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '_FaultFile delegeert ${invocation.memberName} niet; '
    'voeg de overschrijving toe als de code onder test hem raakt',
  );
}

/// De [Directory]-variant van [_FaultFile]: zelfde afspraak, zelfde leden
/// zolang de code onder test ze raakt.
class _FaultDirectory implements Directory {
  _FaultDirectory(this._delegate, this._failOn, this._error);

  final Directory _delegate;
  final Set<String> _failOn;
  final Object _error;

  void _maybeThrow(String member) {
    if (_failOn.contains(member)) throw _error;
  }

  @override
  String get path => _delegate.path;

  @override
  Future<bool> exists() {
    _maybeThrow('exists');
    return _delegate.exists();
  }

  @override
  bool existsSync() {
    _maybeThrow('existsSync');
    return _delegate.existsSync();
  }

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) {
    _maybeThrow('list');
    return _delegate.list(recursive: recursive, followLinks: followLinks);
  }

  @override
  Future<FileStat> stat() {
    _maybeThrow('stat');
    return _delegate.stat();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '_FaultDirectory delegeert ${invocation.memberName} niet; '
    'voeg de overschrijving toe als de code onder test hem raakt',
  );
}
