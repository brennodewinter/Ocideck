import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../models/settings.dart';
import '../services/web_asset_store.dart';
import '../utils/bundled_asset.dart';
import '../utils/image_limits.dart';
import '../utils/project_path.dart';

/// Het logo uit een stijlprofiel, voor zowel ingebouwde assets als een door de
/// gebruiker gekozen bestand. Ontbrekende bestanden vallen stil terug op een
/// neutraal beeldicoon; een document mag daardoor nooit onbruikbaar worden.
class ThemeProfileLogo extends StatelessWidget {
  const ThemeProfileLogo({
    super.key,
    required this.profile,
    this.projectPath,
    this.width = 96,
    this.height = 48,
    this.alignment = Alignment.center,
    this.logoPath,
  });

  final ThemeProfile profile;
  final String? projectPath;
  final double width;
  final double height;
  final Alignment alignment;
  final String? logoPath;

  @override
  Widget build(BuildContext context) {
    final path = (logoPath ?? profile.logoPath)?.trim() ?? '';
    final image = _provider(path);
    return SizedBox(
      width: width,
      height: height,
      child: image == null
          ? Icon(
              path.isEmpty ? Icons.image_outlined : Icons.broken_image_outlined,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )
          : Image(
              image: image,
              fit: BoxFit.contain,
              alignment: alignment,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => Icon(
                Icons.broken_image_outlined,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
    );
  }

  ImageProvider? _provider(String path) {
    if (path.isEmpty) return null;
    if (isBundledAssetPath(path)) {
      return cappedBundledAssetImage(bundledAssetKey(path));
    }
    if (WebAssetStore.isMemPath(path)) {
      final bytes = WebAssetStore.bytesFor(path);
      return bytes == null ? null : cappedMemoryImage(bytes);
    }
    if (kIsWeb) return null;
    final resolved = resolveTrustedAssetPath(path, projectPath);
    return resolved == null ? null : cappedFileImage(File(resolved));
  }
}
