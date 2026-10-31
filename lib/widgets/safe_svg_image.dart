import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;

import '../services/image_service.dart';
import '../services/web_asset_store.dart';
import '../utils/image_limits.dart';
import '../utils/project_path.dart';
import '../utils/sanitize_svg.dart';

/// Of [path] een geïmporteerd SVG-beeld aanwijst.
///
/// Webafbeeldingen hebben een `mem:`-sleutel zonder extensie; daar is de naam
/// die [WebAssetStore] bij de import bewaarde de bron van waarheid.
bool isSvgImagePath(String path) {
  final name = WebAssetStore.isMemPath(path)
      ? WebAssetStore.nameFor(path) ?? ''
      : path;
  return p.extension(name).toLowerCase() == '.svg';
}

/// Een SVG-afbeelding die vóór het tekenen door OciDecks allow-list gaat.
///
/// Ook bestaande bestanden die iemand handmatig in een Library-map zette
/// worden hierdoor niet rechtstreeks aan de renderer gevoerd. Een ongeldige of
/// te grote SVG gebruikt [errorBuilder], net als een mislukte rasterdecode.
class SafeSvgImage extends StatefulWidget {
  const SafeSvgImage.file(
    String path, {
    super.key,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.semanticLabel,
    this.projectPath,
    required this.errorBuilder,
    this.errorBuilderWithCause,
  }) : _path = path,
       _bytes = null;

  const SafeSvgImage.memory(
    Uint8List bytes, {
    super.key,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.semanticLabel,
    required this.errorBuilder,
    this.errorBuilderWithCause,
  }) : _path = null,
       _bytes = bytes,
       projectPath = null;

  final String? _path;
  final Uint8List? _bytes;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final double? width;
  final double? height;
  final String? semanticLabel;
  final String? projectPath;
  final WidgetBuilder errorBuilder;
  final Widget Function(BuildContext context, Object? error)?
  errorBuilderWithCause;

  @override
  State<SafeSvgImage> createState() => _SafeSvgImageState();
}

class _SafeSvgData {
  const _SafeSvgData(this.svg, this.embeddedPng);

  final String svg;
  final Uint8List? embeddedPng;
}

class _SafeSvgImageState extends State<SafeSvgImage> {
  late Future<_SafeSvgData?> _safeSvg = _begin();

  /// Het laatst gelukte beeld. Een wissel van dia mag niet eerst een leeg
  /// vlak tonen terwijl de volgende SVG nog wordt opgeschoond (#2682).
  _SafeSvgData? _visible;

  Future<_SafeSvgData?> _begin() {
    final future = _load();
    future.then((data) {
      if (data != null) _visible = data;
    }, onError: (_, _) {});
    return future;
  }

  @override
  void didUpdateWidget(SafeSvgImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._path != widget._path ||
        !identical(oldWidget._bytes, widget._bytes) ||
        oldWidget.projectPath != widget.projectPath) {
      _safeSvg = _begin();
    }
  }

  Future<_SafeSvgData?> _load() {
    if (widget._bytes case final memory?) {
      return _cachedSvg(_MemKey(memory), () async => memory);
    }
    if (widget._path case final path?) {
      final known = _byPath[path];
      final hit = known == null ? null : _touch(known);
      if (hit != null && hit.svg != null && known != null) {
        _revalidate(path, known);
        return SynchronousFuture(_SafeSvgData(hit.svg!, hit.png));
      }
      return _loadFile(path);
    }
    return SynchronousFuture(null);
  }

  Future<_SafeSvgData?> _loadFile(String path) async {
    var file = File(path);
    if (widget.projectPath case final projectPath?) {
      final real = await containedRealPathOrNull(path, projectPath);
      if (real == null) throw ProjectEscapeException(path);
      file = File(real);
    }
    final stat = await file.stat();
    if (stat.size <= 0 || stat.size > ImageService.maxImageBytes) return null;
    final key = _FileKey(
      file.path,
      stat.modified.millisecondsSinceEpoch,
      stat.size,
    );
    return _cachedSvg(key, () => file.readAsBytes(), rememberAs: path);
  }

  /// De cache-treffer is synchroon. De stempel controleren we daarna: een
  /// bestand dat intussen werd overschreven mag de oude SVG niet houden.
  Future<void> _revalidate(String path, _FileKey shown) async {
    File file;
    try {
      file = File(shown.path);
      if (widget.projectPath case final projectPath?) {
        final real = await containedRealPathOrNull(path, projectPath);
        if (real == null) throw ProjectEscapeException(path);
        file = File(real);
      }
      final stat = await file.stat();
      if (!mounted || widget._path != path) return;
      final same =
          stat.modified.millisecondsSinceEpoch == shown.mtimeMs &&
          stat.size == shown.length;
      if (same) return;
      if (_byPath[path] == shown) _byPath.remove(path);
      setState(() => _safeSvg = _begin());
    } catch (e) {
      if (!mounted || widget._path != path) return;
      if (_byPath[path] == shown) _byPath.remove(path);
      setState(() => _safeSvg = Future.error(e));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_SafeSvgData?>(
    future: _safeSvg,
    builder: (context, snapshot) {
      final pending = snapshot.connectionState != ConnectionState.done;
      if (pending && _visible != null) return _paint(context, _visible!);
      if (pending) return SizedBox(width: widget.width, height: widget.height);
      if (snapshot.hasError) {
        return widget.errorBuilderWithCause?.call(context, snapshot.error) ??
            widget.errorBuilder(context);
      }
      final data = snapshot.data;
      if (data == null) {
        return widget.errorBuilderWithCause?.call(context, null) ??
            widget.errorBuilder(context);
      }
      return _paint(context, data);
    },
  );

  Widget _paint(BuildContext context, _SafeSvgData data) {
    if (data.embeddedPng case final png?) {
      return ResolvedDecodeImage(
        explicitEdge: null,
        imageFor: (plan) => cappedMemoryImage(png, maxEdge: plan.edge),
        child: (image) => Image(
          image: image,
          fit: widget.fit,
          alignment: widget.alignment,
          width: widget.width,
          height: widget.height,
          semanticLabel: widget.semanticLabel,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) =>
              widget.errorBuilder(context),
        ),
      );
    }
    return SvgPicture.string(
      data.svg,
      fit: widget.fit,
      alignment: widget.alignment,
      width: widget.width,
      height: widget.height,
      semanticsLabel: widget.semanticLabel,
      placeholderBuilder: widget.errorBuilder,
      errorBuilder: (context, error, stackTrace) =>
          widget.errorBuilder(context),
    );
  }
}

/// Boven deze grootte schoont [sanitizeImportedSvgForDisplay] op een
/// achtergrond-isolate. De cache hier houdt het resultaat vast (#2682).
const int _maxSvgCacheBytes = 32 * 1024 * 1024;

void debugResetSvgCache() {
  debugImportedSvgSanitizeCount = 0;
  _svgCache.clear();
  _svgCacheBytes = 0;
  _svgInflight.clear();
  _byPath.clear();
}

final Map<Object, _SvgCacheEntry> _svgCache = {};
final Map<Object, Future<_SafeSvgData?>> _svgInflight = {};
final Map<String, _FileKey> _byPath = {};
int _svgCacheBytes = 0;

class _MemKey {
  _MemKey(this.bytes);
  final Uint8List bytes;

  @override
  bool operator ==(Object other) =>
      other is _MemKey && identical(bytes, other.bytes);

  @override
  int get hashCode => identityHashCode(bytes);
}

class _FileKey {
  const _FileKey(this.path, this.mtimeMs, this.length);
  final String path;
  final int mtimeMs;
  final int length;

  @override
  bool operator ==(Object other) =>
      other is _FileKey &&
      path == other.path &&
      mtimeMs == other.mtimeMs &&
      length == other.length;

  @override
  int get hashCode => Object.hash(path, mtimeMs, length);
}

class _SvgCacheEntry {
  const _SvgCacheEntry(this.svg, this.png, this.weight);
  final String? svg;
  final Uint8List? png;
  final int weight;
}

Future<_SafeSvgData?> _cachedSvg(
  Object key,
  Future<Uint8List> Function() read, {
  String? rememberAs,
}) {
  final hit = _touch(key);
  if (hit != null) return SynchronousFuture(_entryData(hit));
  final pending = _svgInflight[key];
  if (pending != null) return pending;
  final future = _readAndStore(key, read, rememberAs: rememberAs);
  _svgInflight[key] = future;
  future.whenComplete(() => _svgInflight.remove(key));
  return future;
}

Future<_SafeSvgData?> _readAndStore(
  Object key,
  Future<Uint8List> Function() read, {
  String? rememberAs,
}) async {
  final bytes = await read();
  final sanitized = await sanitizeImportedSvgForDisplay(bytes);
  final png = sanitized?.embeddedPng;
  final entry = _SvgCacheEntry(
    sanitized?.svg,
    png,
    sanitized == null ? 1 : sanitized.svg.length + (png?.length ?? 0),
  );
  if (entry.weight <= _maxSvgCacheBytes) {
    _store(key, entry, rememberAs: rememberAs);
  }
  return _entryData(entry);
}

_SafeSvgData? _entryData(_SvgCacheEntry entry) {
  final svg = entry.svg;
  if (svg == null) return null;
  return _SafeSvgData(svg, entry.png);
}

_SvgCacheEntry? _touch(Object key) {
  final hit = _svgCache.remove(key);
  if (hit == null) return null;
  _svgCache[key] = hit;
  return hit;
}

void _store(Object key, _SvgCacheEntry entry, {String? rememberAs}) {
  final previous = _svgCache.remove(key);
  if (previous != null) _svgCacheBytes -= previous.weight;
  _svgCache[key] = entry;
  _svgCacheBytes += entry.weight;
  if (key is _FileKey) {
    _byPath[key.path] = key;
    if (rememberAs != null) _byPath[rememberAs] = key;
  }
  while (_svgCacheBytes > _maxSvgCacheBytes && _svgCache.isNotEmpty) {
    final oldest = _svgCache.keys.first;
    final evicted = _svgCache.remove(oldest)!;
    _svgCacheBytes -= evicted.weight;
    if (oldest is _FileKey) {
      _byPath.removeWhere((_, stored) => stored == oldest);
    }
  }
}
