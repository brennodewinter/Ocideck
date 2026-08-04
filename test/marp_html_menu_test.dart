import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/markdown_service.dart';

/// Reads the vendored libraries straight from the repo (tests run at the root).
Future<String> _diskLoader(String asset) => File(asset).readAsString();

/// A menu deck: a menu slide with a target block, a target-with-image block and
/// a plain text block, plus the two slides those blocks point at.
String _menuDeckMarkdown() {
  final md = MarkdownService();
  final deck = Deck(
    title: 'Demo',
    slides: [
      Slide.create(SlideType.menu).copyWith(
        title: 'Kies een onderwerp',
        anchor: 'hoofdmenu',
        bullets: [
          '[Prijzen](#prijzen)',
          '[Demo](#demo) ![](mem:9f2a1c)',
          'Platte tekst',
        ],
      ),
      Slide.create(
        SlideType.bullets,
      ).copyWith(title: 'Prijzen', anchor: 'prijzen', bullets: ['x']),
      Slide.create(
        SlideType.bullets,
      ).copyWith(title: 'Demo', anchor: 'demo', bullets: ['y']),
    ],
  );
  return md.generateDeck(deck, forExport: true);
}

void main() {
  group('menu slide in the HTML export', () {
    test('renders a card grid instead of a plain link list', () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      final html = await service.build(_menuDeckMarkdown());

      // The grid container carries the column count the preview would pick for
      // three blocks (2 columns).
      expect(
        html,
        contains(
          '<div class="menu-grid" style="grid-template-columns:repeat(2,1fr)">',
        ),
      );
      // The blocks are no longer emitted as raw `- [..](#..)` bullet markdown.
      expect(html, isNot(contains('- [Prijzen](#prijzen)')));
    });

    test(
      'a target block is a link to its anchor with an accent border',
      () async {
        final service = MarpHtmlService(loadAsset: _diskLoader);
        final html = await service.build(_menuDeckMarkdown());

        expect(
          html,
          contains(
            '<a class="menu-card" href="#prijzen" '
            'style="border-color:#0033998c;background:#0033991a">',
          ),
        );
        expect(html, contains('<div class="menu-label">Prijzen</div>'));
      },
    );

    test('a plain block is a div with a muted (text-colour) border', () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      final html = await service.build(_menuDeckMarkdown());

      // No href — a text block never navigates.
      expect(html, contains('<div class="menu-card" style="border-color:'));
      expect(html, contains('<div class="menu-label">Platte tekst</div>'));
      // The plain border is not the accent border used for target blocks.
      final plain = RegExp(
        r'<div class="menu-card" style="border-color:(#[0-9a-f]{8})',
      ).firstMatch(html)!.group(1);
      expect(plain, isNot('#0033998c'));
    });

    test('an image block embeds the image as a thumbnail', () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      final html = await service.build(
        _menuDeckMarkdown(),
        // A resolver makes the mem: reference a real embedded image, so the
        // export is self-contained and the src becomes the dedupe placeholder.
        embedImage: (src) async =>
            'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      );

      expect(
        html,
        contains('<img class="menu-thumb" alt="" src="#ocideck-img-0">'),
      );
    });

    test('the target slides carry an id so the fragment links land', () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      final html = await service.build(_menuDeckMarkdown());

      // marked (v18) generates no heading ids; without a section id the
      // `#prijzen`/`#demo` links would scroll nowhere.
      expect(html, contains('<section class="slide" id="hoofdmenu"'));
      expect(html, contains('<section class="slide" id="prijzen"'));
      expect(html, contains('<section class="slide" id="demo"'));
    });

    test('the grid styling ships in the base stylesheet', () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      final html = await service.build(_menuDeckMarkdown());
      expect(html, contains('.slide .menu-card'));
      expect(html, contains('grid-auto-rows:200px'));
    });

    test('a block label is HTML-escaped, never injected as markup', () async {
      final md = MarkdownService();
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.menu).copyWith(
            title: 'Menu',
            anchor: 'menu',
            bullets: ['<img src=x onerror=alert(1)>'],
          ),
        ],
      );
      final service = MarpHtmlService(loadAsset: _diskLoader);
      final html = await service.build(md.generateDeck(deck, forExport: true));
      expect(
        html,
        contains(
          '<div class="menu-label">'
          '&lt;img src=x onerror=alert(1)&gt;</div>',
        ),
      );
      expect(html, isNot(contains('<img src=x onerror')));
    });
  });
}
