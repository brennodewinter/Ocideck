import 'package:flutter/material.dart';

import '../../models/slide.dart';
import '../../models/document_signature.dart';
import '../slides/slide_preview.dart';

Widget editorSlidePreview(
  Slide slide, {
  String? projectPath,
  DocumentSignature? deckSignature,
}) => AspectRatio(
  aspectRatio: 16 / 9,
  child: DecoratedBox(
    decoration: BoxDecoration(
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.16),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: SlidePreviewWidget(
      slide: slide,
      projectPath: projectPath,
      deckSignature: deckSignature,
    ),
  ),
);
