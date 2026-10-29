import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  late Future<_SafeSvgData?> _safeSvg = _load();

  @override
  void didUpdateWidget(SafeSvgImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._path != widget._path ||
        oldWidget._bytes != widget._bytes ||
        oldWidget.projectPath != widget.projectPath) {
      _safeSvg = _load();
    }
  }

  Future<_SafeSvgData?> _load() async {
    Uint8List bytes;
    if (widget._bytes case final memory?) {
      bytes = memory;
    } else if (widget._path case final path?) {
      var file = File(path);
      if (widget.projectPath case final projectPath?) {
        final real = await containedRealPathOrNull(path, projectPath);
        if (real == null) throw ProjectEscapeException(path);
        file = File(real);
      }
      final length = await file.length();
      if (length <= 0 || length > ImageService.maxImageBytes) return null;
      bytes = await file.readAsBytes();
    } else {
      return null;
    }
    final safe = sanitizeImportedSvgBytes(bytes);
    if (safe == null) return null;
    final svg = utf8.decode(safe);
    return _SafeSvgData(svg, extractSoleEmbeddedPng(svg));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_SafeSvgData?>(
    future: _safeSvg,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return SizedBox(width: widget.width, height: widget.height);
      }
      if (snapshot.hasError) {
        return widget.errorBuilderWithCause?.call(context, snapshot.error) ??
            widget.errorBuilder(context);
      }
      final data = snapshot.data;
      if (data == null) {
        return widget.errorBuilderWithCause?.call(context, null) ??
            widget.errorBuilder(context);
      }
      if (data.embeddedPng case final png?) {
        return Image(
          image: cappedMemoryImage(png),
          fit: widget.fit,
          alignment: widget.alignment,
          width: widget.width,
          height: widget.height,
          semanticLabel: widget.semanticLabel,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) =>
              widget.errorBuilder(context),
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
    },
  );
}
