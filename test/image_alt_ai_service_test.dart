import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/models/ai_settings.dart';
import 'package:ocideck/services/ai_client_service.dart';
import 'package:ocideck/services/ai_security_gate.dart';
import 'package:ocideck/services/image_alt_ai_service.dart';

class _FakeTransport implements AiHttpTransport {
  String? lastBody;
  AiHttpResult result = const AiHttpResult(
    200,
    '{"choices":[{"message":{"content":"draft"}}]}',
  );

  @override
  Future<AiHttpResult> send({
    required String method,
    required Uri url,
    required AiResolveStrategy strategy,
    Map<String, String> headers = const {},
    String? body,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    lastBody = body;
    return result;
  }
}

const _localSettings = AiSettings(
  enabled: true,
  mode: AiBackendMode.local,
  baseUrl: 'http://127.0.0.1:11434/v1',
  model: 'gemma3:4b',
);

void main() {
  group('cleanAltDraft', () {
    test('strips a leading "image of/photo of" phrase and capitalises', () {
      expect(cleanAltDraft('Photo of a cat on a sofa'), 'A cat on a sofa');
      expect(cleanAltDraft('an image showing a bar chart'), 'A bar chart');
      expect(cleanAltDraft('afbeelding van een hond'), 'Een hond');
    });

    test('unwraps surrounding quotes and collapses whitespace', () {
      expect(cleanAltDraft('"A   red\nbarn"'), 'A red barn');
    });

    test('caps an over-long draft', () {
      final long = 'word ' * 100;
      final out = cleanAltDraft(long, maxChars: 40);
      expect(out.length, lessThanOrEqualTo(41)); // 40 + the ellipsis
      expect(out.endsWith('…'), isTrue);
    });
  });

  group('resizeImageForVision', () {
    test('downscales the longest edge to the cap and emits JPEG', () {
      final png = img.encodePng(img.Image(width: 3000, height: 1000));
      final out = resizeImageForVision(png);
      // JPEG magic bytes.
      expect(out[0], 0xFF);
      expect(out[1], 0xD8);
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, kVisionMaxEdge);
      // Height scales proportionally (the resizer may round by ±1).
      expect(decoded.height, closeTo(1000 * kVisionMaxEdge / 3000, 1));
    });

    test('leaves a within-cap image at its size (re-encoded as JPEG)', () {
      final png = img.encodePng(img.Image(width: 400, height: 300));
      final decoded = img.decodeImage(resizeImageForVision(png))!;
      expect(decoded.width, 400);
      expect(decoded.height, 300);
    });
  });

  group('buildAltTextRequest', () {
    test('produces a multimodal user message with the image part', () {
      final req = buildAltTextRequest(
        model: 'gemma3:4b',
        imageDataUri: 'data:image/jpeg;base64,AAAA',
        languageName: 'Nederlands',
      );
      final json = req.toJson();
      expect(json['model'], 'gemma3:4b');
      final messages = json['messages'] as List;
      expect(messages.first['role'], 'system');
      final user = messages[1] as Map;
      expect(user['role'], 'user');
      final content = user['content'] as List;
      expect(content.any((p) => p['type'] == 'text'), isTrue);
      final image = content.firstWhere((p) => p['type'] == 'image_url') as Map;
      expect((image['image_url'] as Map)['url'], 'data:image/jpeg;base64,AAAA');
    });
  });

  group('ImageAltAiService.suggestAltText', () {
    test('sends the image and returns the cleaned draft', () async {
      final fake = _FakeTransport()
        ..result = const AiHttpResult(
          200,
          '{"choices":[{"message":{"content":"Photo of a mountain lake"}}]}',
        );
      final client = AiClientService(
        settings: _localSettings,
        hasOutboundConsent: false,
        transport: fake,
        isWeb: false,
      );
      final png = img.encodePng(img.Image(width: 64, height: 64));
      final draft = await ImageAltAiService(
        client,
      ).suggestAltText(imageBytes: png, languageName: 'English');
      expect(draft, 'A mountain lake');
      expect(fake.lastBody, contains('data:image/jpeg;base64,'));
    });
  });

  group('cleanTagsDraft', () {
    test('splits, trims, de-duplicates and caps', () {
      expect(cleanTagsDraft('cat, dog, Cat , , bird'), 'cat, dog, bird');
      expect(
        cleanTagsDraft('1. mountain\n2. lake\n- forest', maxTags: 2),
        'mountain, lake',
      );
    });
  });

  group('ImageAltAiService.suggestTags', () {
    test('returns cleaned comma-separated tags', () async {
      final fake = _FakeTransport()
        ..result = const AiHttpResult(
          200,
          '{"choices":[{"message":{"content":"- mountain\\n- lake\\n- mountain"}}]}',
        );
      final client = AiClientService(
        settings: _localSettings,
        hasOutboundConsent: false,
        transport: fake,
        isWeb: false,
      );
      final png = img.encodePng(img.Image(width: 48, height: 48));
      final tags = await ImageAltAiService(
        client,
      ).suggestTags(imageBytes: png, languageName: 'English');
      expect(tags, 'mountain, lake');
      expect(fake.lastBody, contains('data:image/jpeg;base64,'));
    });
  });
}
