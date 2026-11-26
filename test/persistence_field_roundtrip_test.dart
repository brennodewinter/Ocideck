@Tags(['registration'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/document_style.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';

import 'support/persistence_roundtrip_cases.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final markdown = MarkdownService();
  final files = FileService(
    markdown,
    ImageService(),
    () => const ThemeProfile(),
  );

  Slide reopen(Slide slide) => markdown
      .parseDeck(
        markdown.generateDeck(Deck(title: 'Contract', slides: [slide])),
      )!
      .slides
      .single;

  for (final entry in slideRoundtripCases.entries) {
    test('Slide.${entry.key} survives actual Markdown storage twice', () {
      final probe = entry.value;
      final expected = probe.read(probe.input);
      expect(
        expected,
        isNot(equals(probe.read(probe.base))),
        reason: '${entry.key}: a default-only fixture cannot detect loss',
      );
      final reopened = reopen(probe.input);
      expect(probe.read(reopened), expected, reason: entry.key);
      expect(
        probe.read(reopen(reopened)),
        expected,
        reason: '${entry.key}: second save',
      );
    });
  }

  for (final entry in themeRoundtripCases.entries) {
    final probe = entry.value;
    test('ThemeProfile.${entry.key} survives settings JSON', () {
      final expected = probe.read(probe.input);
      expect(
        expected,
        isNot(equals(probe.read(probe.base))),
        reason: '${entry.key}: a default-only fixture cannot detect loss',
      );
      final stored = jsonDecode(jsonEncode(probe.input.toJson())) as Map;
      final reopened = ThemeProfile.fromJson(Map<String, Object?>.from(stored));
      expect(probe.read(reopened), expected, reason: entry.key);
    });

    test(
      'document style ${entry.key} survives portable profile and document selection',
      () async {
        final built = await files.buildStyleProfileBytes(probe.input);
        final reopened = await files.importStyleProfileBytes(built.bytes);
        expect(reopened.failure, isNull);
        expect(reopened.profile, isNotNull);
        const body = '# Document\r\n\r\nBody without a trailing newline';
        final authored = MarkdownDocument.parse(
          body,
        ).withStyleName(probe.input.name);
        final document = MarkdownDocument.parse(
          utf8.decode(authored.toBytes()),
        );
        expect(document.styleName, probe.input.name);
        expect(document.body, body);
        final resolved = resolveDocumentStyleProfile(
          AppSettings(themeProfiles: [reopened.profile!]),
          document.styleName,
        );
        expect(resolved, isNotNull);
        expect(
          probe.read(resolved!),
          probe.read(probe.input),
          reason: entry.key,
        );
      },
    );
  }

  test('renderPage is a render copy, not a second authored slide', () {
    final original = Slide.create(
      SlideType.freeMarkdown,
    ).copyWith(title: 'Authored', customMarkdown: 'Page one\n\nPage two');
    final serialized = markdown.generateDeck(
      Deck(
        title: 'Contract',
        slides: [original, original.copyWith(renderPage: 1)],
      ),
    );
    final reopened = markdown.parseDeck(serialized)!;
    expect(reopened.slides, hasLength(1));
    expect(reopened.slides.single.renderPage, 0);
    expect(reopened.slides.single.customMarkdown, original.customMarkdown);
  });

  test('projection flags reset and parse-time identity is regenerated', () {
    final original = Slide.create(SlideType.bullets).copyWith(
      title: 'Authored',
      bullets: ['Source content'],
      mediaRedacted: true,
      contentRedacted: true,
    );
    final reopened = reopen(original);
    expect(reopened.mediaRedacted, isFalse);
    expect(reopened.contentRedacted, isFalse);
    expect(reopened.bullets, original.bullets);
    expect(reopened.id, isNot(original.id));
  });
}
