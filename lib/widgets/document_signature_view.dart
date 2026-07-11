import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/document_signature.dart';
import '../utils/log.dart' show logError;

/// A small, reusable render of a [DocumentSignature]: the attested statement,
/// the signature itself (an optional image and/or a typed name), and the
/// signer's name, role and date. Deliberately simple — NO freehand drawing — so
/// it can be reused anywhere (the pentest sign-off slide is a later consumer).
///
/// The optional signature image is only rendered for an embedded `data:` URI
/// (via [Image.memory]); other paths fall back to the typed name so the widget
/// stays cross-platform and pulls in no image-resolution machinery.
class DocumentSignatureView extends StatelessWidget {
  final DocumentSignature signature;

  /// Compact layout (smaller type, tighter spacing) for previews and badges.
  final bool compact;

  const DocumentSignatureView({
    super.key,
    required this.signature,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (signature.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final scale = compact ? 0.85 : 1.0;

    final metaParts = <String>[
      if (signature.name.isNotEmpty) signature.name,
      if (signature.role.isNotEmpty) signature.role,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (signature.statement.isNotEmpty) ...[
          Text(
            signature.statement,
            style: TextStyle(
              fontSize: 13 * scale,
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 12 * scale),
        ],
        _signatureMark(theme, scale),
        SizedBox(height: 6 * scale),
        Container(
          width: 180 * scale,
          height: 1,
          color: muted.withValues(alpha: 0.5),
        ),
        SizedBox(height: 4 * scale),
        if (metaParts.isNotEmpty)
          Text(
            metaParts.join(' · '),
            style: TextStyle(
              fontSize: 12 * scale,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        if (signature.certification.isNotEmpty)
          Text(
            signature.certification,
            style: TextStyle(fontSize: 11 * scale, color: muted),
          ),
        if (signature.date.isNotEmpty)
          Text(
            signature.date,
            style: TextStyle(fontSize: 11 * scale, color: muted),
          ),
      ],
    );
  }

  /// The signature "mark": the embedded image when present and renderable,
  /// otherwise the typed name in a handwriting-like italic.
  Widget _signatureMark(ThemeData theme, double scale) {
    final image = _embeddedImage();
    if (image != null) {
      return Image.memory(
        image,
        height: 44 * scale,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _typedMark(theme, scale),
      );
    }
    return _typedMark(theme, scale);
  }

  Widget _typedMark(ThemeData theme, double scale) {
    final text = signature.typedSignature.isNotEmpty
        ? signature.typedSignature
        : signature.name;
    if (text.isEmpty) return SizedBox(height: 8 * scale);
    return Text(
      text,
      style: TextStyle(
        fontSize: 22 * scale,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w500,
        color: theme.colorScheme.onSurface,
      ),
    );
  }

  /// Decode an embedded `data:...;base64,...` image path, or null when the path
  /// is empty, not a data URI, or malformed.
  Uint8List? _embeddedImage() {
    final path = signature.imagePath;
    if (!path.startsWith('data:')) return null;
    final comma = path.indexOf(',');
    if (comma == -1 || !path.substring(0, comma).contains('base64')) {
      return null;
    }
    try {
      return base64Decode(path.substring(comma + 1));
    } catch (e, s) {
      logError('DocumentSignatureView: decode data-URI signature image', e, s);
      return null;
    }
  }
}
