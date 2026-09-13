import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../theme/app_theme.dart';
import '../../utils/image_limits.dart' show boundedFileImage;
import '../../utils/project_path.dart';

Widget findingEvidenceThumb({
  required bool isVideo,
  required bool isPdf,
  required String path,
  required String? projectPath,
}) {
  if (!isVideo && !isPdf && path.isNotEmpty) {
    final resolved = resolveEditorAssetPath(path, projectPath);
    if (resolved != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image(
          image: boundedFileImage(File(resolved), 176),
          fit: BoxFit.cover,
          // Four times the 44 logical-pixel thumbnail stays sharp at realistic
          // device ratios without decoding a full evidence screenshot.
          errorBuilder: (_, _, _) => findingEvidenceIcon(isVideo, isPdf),
        ),
      );
    }
  }
  return findingEvidenceIcon(isVideo, isPdf);
}

Widget findingEvidenceIcon(bool isVideo, bool isPdf) => Container(
  decoration: BoxDecoration(
    color: AppTheme.slate100,
    borderRadius: BorderRadius.circular(4),
  ),
  child: Icon(
    isPdf
        ? Icons.picture_as_pdf_outlined
        : isVideo
        ? Icons.movie_outlined
        : Icons.image_outlined,
    size: 16,
    color: AppTheme.slate400,
  ),
);
