import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'ai_client_service.dart';
import 'ai_request.dart';

/// The image-tagging consumer of the shared, optional AI backend (AI_ASSIST §6):
/// suggest **WCAG alt-text** for an image using a local vision model. Draft-only
/// — the caller inserts the result for a human to review and never auto-applies
/// it. The pure helpers ([resizeImageForVision], [buildAltTextRequest],
/// [cleanAltDraft]) are network-free and directly unit-testable.

/// Longest edge (px) an image is downscaled to before sending (AI_ASSIST §6.3):
/// big enough for a good caption, small enough to bound payload/latency (base64
/// adds ~33%; vision models tile/downscale internally anyway).
const int kVisionMaxEdge = 1568;

/// Decode [bytes] (any supported format), downscale the longest edge to
/// [kVisionMaxEdge] when larger, and re-encode as JPEG. Returns the original
/// bytes when decoding fails, so the caller still sends something valid. Pure and
/// synchronous, so it runs inside [compute] off the UI isolate.
Uint8List resizeImageForVision(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final longest = decoded.width >= decoded.height
      ? decoded.width
      : decoded.height;
  if (longest <= kVisionMaxEdge) return img.encodeJpg(decoded, quality: 85);
  final resized = decoded.width >= decoded.height
      ? img.copyResize(
          decoded,
          width: kVisionMaxEdge,
          interpolation: img.Interpolation.average,
        )
      : img.copyResize(
          decoded,
          height: kVisionMaxEdge,
          interpolation: img.Interpolation.average,
        );
  return img.encodeJpg(resized, quality: 85);
}

/// A `data:image/jpeg;base64,…` URI for [jpeg], the only image form the `/v1`
/// layer accepts (AI_ASSIST §6.3).
String jpegDataUri(Uint8List jpeg) =>
    'data:image/jpeg;base64,${base64Encode(jpeg)}';

/// Build the multimodal request for **searchable keyword tags** (AI_ASSIST §6):
/// a handful of comma-separated keywords, not a sentence, for the image library
/// search sidecar.
AiChatRequest buildTagsRequest({
  required String model,
  required String imageDataUri,
  required String languageName,
}) {
  final instruction =
      'List 5 to 8 short, searchable keyword tags for this image, in '
      '$languageName, separated by commas. Use single words or very short '
      'phrases (objects, subjects, setting, colours, type of image). No '
      'sentences, no numbering, no explanation — only the comma-separated tags.';
  return AiChatRequest(
    model: model,
    maxTokens: 80,
    messages: [
      AiMessage.text(AiRole.system, AiPrompts.systemGuardrail),
      AiMessage(AiRole.user, [
        AiTextPart(instruction),
        AiImagePart(imageDataUri),
      ]),
    ],
  );
}

/// Tidy a raw model tag list into a clean, de-duplicated comma-separated string:
/// split on commas/newlines, drop numbering/bullets and empties, lower-case for
/// dedup, cap the count.
String cleanTagsDraft(String raw, {int maxTags = 8}) {
  final seen = <String>{};
  final tags = <String>[];
  for (final part in raw.split(RegExp(r'[,\n;]'))) {
    var t = part.trim().replaceFirst(RegExp(r'^[\-\*\d.\)\s]+'), '').trim();
    if (t.isEmpty) continue;
    final key = t.toLowerCase();
    if (seen.add(key)) tags.add(t);
    if (tags.length >= maxTags) break;
  }
  return tags.join(', ');
}

/// Build the multimodal alt-text request: the shared guardrail + a concise,
/// locale-aware per-field instruction + the image part (object form).
AiChatRequest buildAltTextRequest({
  required String model,
  required String imageDataUri,
  required String languageName,
}) {
  final instruction =
      'Write concise WCAG alt-text (about one sentence, at most ~125 '
      'characters) describing the meaningful content or function of this image, '
      'in $languageName. Do NOT start with "image of", "photo of" or "picture '
      'of" — assistive technology already announces that it is an image. Return '
      'only the alt-text itself, with no quotes, preamble or explanation.';
  return AiChatRequest(
    model: model,
    maxTokens: 120,
    messages: [
      AiMessage.text(AiRole.system, AiPrompts.systemGuardrail),
      AiMessage(AiRole.user, [
        AiTextPart(instruction),
        AiImagePart(imageDataUri),
      ]),
    ],
  );
}

final _reLeadingImagePrefix = RegExp(
  r'^\s*(an?\s+)?(image|photo(graph)?|picture|screenshot|afbeelding|foto)\s+'
  r'(of|showing|that shows|van|met)\s+',
  caseSensitive: false,
);

/// Tidy a raw model draft into alt-text: unwrap surrounding quotes, strip a
/// leading "image of/…" phrase, collapse whitespace, and cap the length so an
/// over-eager model can't emit a paragraph (AI_ASSIST §6.4).
String cleanAltDraft(String raw, {int maxChars = 250}) {
  var text = raw.trim();
  if (text.length >= 2 &&
      ((text.startsWith('"') && text.endsWith('"')) ||
          (text.startsWith('“') && text.endsWith('”')))) {
    text = text.substring(1, text.length - 1).trim();
  }
  text = text
      .replaceFirst(_reLeadingImagePrefix, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (text.isNotEmpty) {
    text = text[0].toUpperCase() + text.substring(1);
  }
  if (text.length > maxChars) {
    text = '${text.substring(0, maxChars).trimRight()}…';
  }
  return text;
}

/// Wraps a gated [AiClientService] as the alt-text vision consumer.
class ImageAltAiService {
  ImageAltAiService(this._client);

  final AiClientService _client;

  /// Suggest alt-text for [imageBytes] in [languageName]. Resizes off the UI
  /// isolate, sends the multimodal request through the gated client, and returns
  /// the cleaned draft (empty = no suggestion). Propagates the client's
  /// `AiGateException` / `AiRequestException` so the caller can show a graceful
  /// message and fall back to manual entry.
  Future<String> suggestAltText({
    required Uint8List imageBytes,
    required String languageName,
  }) async {
    final jpeg = await compute(resizeImageForVision, imageBytes);
    final request = buildAltTextRequest(
      model: _client.settings.model,
      imageDataUri: jpegDataUri(jpeg),
      languageName: languageName,
    );
    return cleanAltDraft((await _client.chat(request)).text);
  }

  /// Suggest searchable keyword tags (comma-separated) for [imageBytes] in
  /// [languageName], for the image-library search sidecar. Same resize/gate path
  /// as [suggestAltText]; returns the cleaned tag string (empty = none).
  Future<String> suggestTags({
    required Uint8List imageBytes,
    required String languageName,
  }) async {
    final jpeg = await compute(resizeImageForVision, imageBytes);
    final request = buildTagsRequest(
      model: _client.settings.model,
      imageDataUri: jpegDataUri(jpeg),
      languageName: languageName,
    );
    return cleanTagsDraft((await _client.chat(request)).text);
  }
}
