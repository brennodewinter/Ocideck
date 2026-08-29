import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/export_metadata.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/odp/deck_odp_export.dart';
import 'package:ocideck/services/pptx/deck_pptx_export.dart';
import 'package:ocideck/widgets/slides/previews/callout_overlay.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// De toegankelijkheidspoort voor beeldverwijzingen (#1844, IMAGE_CALLOUTS.md
/// §12).
///
/// De DOM-kant van `aria-describedby` staat al in
/// `marp_html_service_callouts_test.dart`. Wat hier bij komt is de kant die een
/// schermlezer werkelijk leest: de **semantics-boom** van Flutter, de vraag of
/// een niet-onthulde groep er echt *uit* is in plaats van alleen doorzichtig,
/// en de alt-tekstsleuf van de rasterexports.
///
/// De Flutter-toetsen draaien binnen `tester.runAsync` met een echt PNG op
/// schijf. Dat is geen omslachtigheid: `CalloutOverlay` tekent niets vóór de
/// intrinsieke beeldmaat bekend is, en die maat komt uit een echte decode. Een
/// widgettest die dat overslaat vindt nul markeringen — en bewijst dan even
/// hard "niets getekend" als "alles goed getekend".

/// Alle knopen van de semantics-boom, plat — de boom zoals een schermlezer
/// hem krijgt, niet de widgetboom.
List<SemanticsData> _semanticsTree(WidgetTester tester) {
  final out = <SemanticsData>[];
  void visit(SemanticsNode node) {
    out.add(node.getSemanticsData());
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(tester.semantics.find(find.byType(MaterialApp)));
  return out;
}

List<String> _labels(WidgetTester tester) =>
    _semanticsTree(tester).map((d) => d.label).toList();

List<String> _hints(WidgetTester tester) =>
    _semanticsTree(tester).map((d) => d.hint).toList();

/// Een echt PNG van [w]×[h] op schijf — `CalloutOverlay` heeft de intrinsieke
/// maat nodig en die komt alleen uit een decode.
String _writePng(String dirPrefix, {int w = 200, int h = 100}) {
  final dir = Directory.systemTemp.createTempSync(dirPrefix);
  final file = File('${dir.path}/beeld.png');
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(180, 180, 180));
  file.writeAsBytesSync(Uint8List.fromList(img.encodePng(image)));
  return file.path;
}

Widget _host(Widget child) => MaterialApp(
  home: Center(child: SizedBox(width: 400, height: 300, child: child)),
);

Slide _slideWithCallouts({
  required String imagePath,
  required List<ImageCallout> callouts,
  List<String> bullets = const [],
  bool mediaRedacted = false,
  BulletRevealMode reveal = BulletRevealMode.all,
}) => Slide(
  id: 'dia',
  anchor: 'dia-1',
  type: SlideType.bulletsImage,
  title: 'De pomp',
  bullets: bullets,
  imagePath: imagePath,
  callouts: callouts,
  calloutReveal: reveal,
  mediaRedacted: mediaRedacted,
);

const _twoBolts = ImageCallout(
  reference: 'A',
  targets: [CalloutPoint(0.610, 0.480), CalloutPoint(0.700, 0.300)],
  description: 'de twee bevestigingsbouten',
);

const _inlet = ImageCallout(
  reference: 'B',
  targets: [CalloutPoint(0.200, 0.200)],
  description: 'de inlaat',
);

void main() {
  group('Flutter semantics-spiegel (§12.2)', () {
    testWidgets('markering met één target: "referentie, beschrijving"', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final handle = tester.ensureSemantics();
        final path = _writePng('ocideck_a11y_one');
        await tester.pumpWidget(
          _host(
            CalloutOverlay(
              slide: _slideWithCallouts(imagePath: path, callouts: [_inlet]),
              profile: const ThemeProfile(),
              slotWidth: 400,
              slotHeight: 300,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pump();

        expect(_labels(tester), contains('B, de inlaat'));
        handle.dispose();
      });
    });

    testWidgets('meerdere targets: elk een eigen "target n of m"', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final handle = tester.ensureSemantics();
        final path = _writePng('ocideck_a11y_multi');
        await tester.pumpWidget(
          _host(
            CalloutOverlay(
              slide: _slideWithCallouts(imagePath: path, callouts: [_twoBolts]),
              profile: const ThemeProfile(),
              slotWidth: 400,
              slotHeight: 300,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pump();

        final labels = _labels(tester);
        expect(
          labels,
          contains('A, de twee bevestigingsbouten, target 1 of 2'),
        );
        expect(
          labels,
          contains('A, de twee bevestigingsbouten, target 2 of 2'),
        );
        // Eén idee, twee ordinalen — nooit een kale, naamloze vorm (§12.1).
        expect(labels, isNot(contains('A')));
        handle.dispose();
      });
    });

    testWidgets(
      'niet-onthulde groep is afwezig uit de boom, niet enkel onzichtbaar',
      (tester) async {
        await tester.runAsync(() async {
          final handle = tester.ensureSemantics();
          final path = _writePng('ocideck_a11y_reveal');
          final slide = _slideWithCallouts(
            imagePath: path,
            callouts: [_twoBolts, _inlet],
          );

          // Stap 1: alleen A is onthuld.
          await tester.pumpWidget(
            _host(
              CalloutOverlay(
                slide: slide,
                profile: const ThemeProfile(),
                slotWidth: 400,
                slotHeight: 300,
                revealedReferences: const {'A'},
              ),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await tester.pump();

          var labels = _labels(tester);
          expect(
            labels,
            contains('A, de twee bevestigingsbouten, target 1 of 2'),
          );
          expect(
            labels.where((l) => l.contains('de inlaat')),
            isEmpty,
            reason:
                'B is nog niet onthuld en hoort dus niet in de '
                'accessibility tree te staan (§7, §12.2)',
          );

          // Stap 2: B komt erbij en verschijnt dan wél.
          await tester.pumpWidget(
            _host(
              CalloutOverlay(
                slide: slide,
                profile: const ThemeProfile(),
                slotWidth: 400,
                slotHeight: 300,
                revealedReferences: const {'A', 'B'},
              ),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await tester.pump();

          labels = _labels(tester);
          expect(labels, contains('B, de inlaat'));
          handle.dispose();
        });
      },
    );

    testWidgets('geredigeerd beeld: geen enkele markering in de boom (§8)', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final handle = tester.ensureSemantics();
        final path = _writePng('ocideck_a11y_redact');
        await tester.pumpWidget(
          _host(
            CalloutOverlay(
              slide: _slideWithCallouts(
                imagePath: path,
                callouts: [_twoBolts, _inlet],
              ),
              profile: const ThemeProfile(),
              slotWidth: 400,
              slotHeight: 300,
              mediaRedacted: true,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pump();

        expect(
          _labels(tester).where((l) => l.contains('bevestigingsbouten')),
          isEmpty,
        );
        expect(_labels(tester).where((l) => l.contains('inlaat')), isEmpty);
        handle.dispose();
      });
    });

    testWidgets('bullet draagt de beschrijving — de aria-describedby-spiegel', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final handle = tester.ensureSemantics();
        final path = _writePng('ocideck_a11y_bullet');
        final slide = _slideWithCallouts(
          imagePath: path,
          callouts: [_twoBolts, _inlet],
          bullets: const [
            'Het pomphuis wordt vastgezet (A)',
            'Water komt hier binnen (B)',
            'Een bullet zonder verwijzing',
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 800,
                  height: 450,
                  child: SlidePreviewWidget(slide: slide),
                ),
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pump();

        final hints = _hints(tester);
        expect(hints, contains('de twee bevestigingsbouten'));
        expect(hints, contains('de inlaat'));
        // Precies één keer per verwijzing: een schermlezer die de bullet leest
        // hoort de betekenis één keer, niet per target.
        expect(hints.where((h) => h == 'de twee bevestigingsbouten').length, 1);
        // Een bullet zonder verwijzing krijgt geen lege hint erbij.
        expect(hints.where((h) => h.isNotEmpty).length, 2);
        handle.dispose();
      });
    });
  });

  group('HTML-export: wat de accessibility tree ziet (§12.2)', () {
    String render(Slide slide) => renderImageCallouts(
      '<div class="split-image">\n![beeld](beeld.png)\n</div>\n'
      '- Het pomphuis wordt vastgezet (A)\n'
      '- Water komt hier binnen (B)\n',
      slide,
    );

    test('verborgen beschrijving blijft leesbaar voor een schermlezer', () {
      // De CSS staat in een `part`-bestand en is niet publiek; de regel zelf is
      // wat telt, dus lezen we de bron. Zo valt de toets om zodra iemand de
      // verbergtruc vervangt, ook zonder een volledige export te renderen.
      final css = File(
        'lib/services/marp_html/marp_html_service_css.dart',
      ).readAsStringSync();
      // `clip: rect(0,0,0,0)` haalt het van het scherm maar láát het in de
      // boom. `display:none` en `visibility:hidden` doen dat niet — die maken
      // de beschrijving onbereikbaar en zouden de hele §12.2-keten stil breken.
      expect(css, contains('.ocideck-callout-desc'));
      expect(css, contains('clip:rect(0,0,0,0)'));
      final descRule = css.substring(
        css.indexOf('.ocideck-callout-desc'),
        css.indexOf('}', css.indexOf('.ocideck-callout-desc')),
      );
      expect(descRule, isNot(contains('display:none')));
      expect(descRule, isNot(contains('visibility:hidden')));
    });

    test('pijlmodus noemt elke verwijzing precies één keer', () {
      // De pijl en de badge wezen naar dezelfde verwijzing en droegen allebei
      // `role="img"` met dezelfde naam, dus een schermlezer las hem twee keer
      // voor. Gevonden in de accessibility tree van een echte browser op een
      // echte export, niet in de markup alleen.
      final html = renderImageCallouts(
        '<div class="split-image">\n![beeld](beeld.png)\n</div>\n'
        '- Het donkere blok links (A)\n',
        Slide(
          id: 'dia',
          anchor: 'dia-1',
          type: SlideType.bulletsImage,
          bullets: const ['Het donkere blok links (A)'],
          imagePath: 'beeld.png',
          calloutPresentation: CalloutPresentation.arrow,
          callouts: const [
            ImageCallout(
              reference: 'A',
              targets: [CalloutPoint(0.255, 0.340)],
              description: 'het donkere blok',
            ),
          ],
        ),
      );
      expect(
        RegExp('aria-label="A, het donkere blok"').allMatches(html).length,
        1,
      );
      // De pijllijn blijft getekend, maar buiten de boom.
      expect(html, contains('class="ocideck-arrow" aria-hidden="true"'));
    });

    test('pijl naar een gebied: het gebied draagt de naam, de pijl niet', () {
      final html = renderImageCallouts(
        '<div class="split-image">\n![beeld](beeld.png)\n</div>\n'
        '- Bedienen doe je hier (A)\n',
        Slide(
          id: 'dia',
          anchor: 'dia-1',
          type: SlideType.bulletsImage,
          bullets: const ['Bedienen doe je hier (A)'],
          imagePath: 'beeld.png',
          calloutPresentation: CalloutPresentation.arrow,
          callouts: const [
            ImageCallout(
              reference: 'A',
              targets: [CalloutRegion(0.180, 0.240, 0.160, 0.200)],
              description: 'het bedieningspaneel',
            ),
          ],
        ),
      );
      expect(
        RegExp('aria-label="A, het bedieningspaneel"').allMatches(html).length,
        1,
      );
      expect(html, contains('class="ocideck-region" role="img"'));
      expect(html, contains('class="ocideck-arrow" aria-hidden="true"'));
    });

    test('markeringen zijn nooit naamloos', () {
      final html = render(
        _slideWithCallouts(
          imagePath: 'beeld.png',
          callouts: [_twoBolts, _inlet],
        ),
      );
      // Elke role="img" draagt een aria-label; een markering mét naam is nooit
      // uit de boom gehaald.
      expect(html, isNot(contains('role="img" aria-hidden')));
      final markers = RegExp('role="img"').allMatches(html).length;
      final labelled = RegExp(
        'role="img" aria-label="',
      ).allMatches(html).length;
      expect(markers, 3);
      expect(labelled, markers);
    });

    test(
      'statische export verbergt niets, en heeft daarom geen live region',
      () {
        // §7: een statische export toont elke groep. Er is dus geen
        // onthulstap om aan te kondigen en geen groep om te verbergen. Deze
        // toets pint dat vast: gaat de HTML-export ooit tóch stappen, dan valt
        // hij om en moet §12.2's live region er alsnog bij komen.
        final html = render(
          _slideWithCallouts(
            imagePath: 'beeld.png',
            callouts: [_twoBolts, _inlet],
            bullets: const [
              'Het pomphuis wordt vastgezet (A)',
              'Water komt hier binnen (B)',
            ],
            reveal: BulletRevealMode.steps,
          ),
        );
        expect(html, isNot(contains('aria-live')));
        expect(html, isNot(contains('hidden>')));
        expect(html, contains('de twee bevestigingsbouten'));
        expect(html, contains('de inlaat'));
      },
    );
  });

  group('Rasterexports: de alt-tekstsleuf (§12.2)', () {
    test('calloutAltText plakt de beschrijvingen achter de bestaande alt', () {
      expect(
        calloutAltText('Schema van de pomp', const [_twoBolts, _inlet]),
        'Schema van de pomp. A: de twee bevestigingsbouten. B: de inlaat.',
      );
    });

    test('geen bestaande alt: alleen de beschrijvingen', () {
      expect(calloutAltText('', const [_inlet]), 'B: de inlaat.');
    });

    test('beschrijvingsloze callout valt weg, punt wordt niet verdubbeld', () {
      const naamloos = ImageCallout(
        reference: 'C',
        targets: [CalloutPoint(0.5, 0.5)],
        description: '',
      );
      expect(calloutAltText('Alt.', const [naamloos]), 'Alt.');
      expect(calloutAltText('', const [naamloos]), '');
    });

    test('PPTX: descr op de vorm, met attribuut-escaping', () {
      const hostile = ImageCallout(
        reference: 'A',
        targets: [CalloutPoint(0.5, 0.5)],
        description: 'de "grote" klep & het <ventiel>',
      );
      final pptx = buildDeckExportPptx(
        [
          Uint8List.fromList(const [1, 2, 3]),
        ],
        metadata: const ExportDocumentMetadata(),
        fallbackTitle: 'deck',
        altTexts: [
          calloutAltText('', const [hostile]),
        ],
      );
      final slideXml = _entry(pptx, 'ppt/slides/slide1.xml');
      expect(slideXml, contains('descr="'));
      expect(slideXml, contains('&quot;grote&quot;'));
      expect(slideXml, contains('&amp;'));
      expect(slideXml, contains('&lt;ventiel&gt;'));
      // Het ruwe aanhalingsteken mag het attribuut niet openbreken.
      expect(slideXml, isNot(contains('de "grote"')));
    });

    test('PPTX zonder alt-tekst: geen leeg descr-attribuut', () {
      final pptx = buildDeckExportPptx(
        [
          Uint8List.fromList(const [1, 2, 3]),
        ],
        metadata: const ExportDocumentMetadata(),
        fallbackTitle: 'deck',
      );
      expect(_entry(pptx, 'ppt/slides/slide1.xml'), isNot(contains('descr=')));
    });

    test('ODP: svg:desc in het frame, met tekst-escaping', () {
      const hostile = ImageCallout(
        reference: 'A',
        targets: [CalloutPoint(0.5, 0.5)],
        description: 'de klep & het <ventiel>',
      );
      final odp = buildDeckExportOdp(
        images: [
          Uint8List.fromList(const [1, 2, 3]),
        ],
        metadata: const ExportDocumentMetadata(),
        fallbackTitle: 'deck',
        altTexts: [
          calloutAltText('Schema', const [hostile]),
        ],
      );
      final content = _entry(odp, 'content.xml');
      expect(
        content,
        contains(
          '<svg:desc>Schema. A: de klep &amp; het &lt;ventiel&gt;.</svg:desc>',
        ),
      );
      // Het element hoort ná de afbeelding, binnen hetzelfde frame.
      expect(
        content.indexOf('<svg:desc>'),
        greaterThan(content.indexOf('<draw:image')),
      );
      expect(
        content.indexOf('<svg:desc>'),
        lessThan(content.indexOf('</draw:frame>')),
      );
    });

    test('ODP zonder alt-tekst: geen leeg svg:desc-element', () {
      final odp = buildDeckExportOdp(
        images: [
          Uint8List.fromList(const [1, 2, 3]),
        ],
        metadata: const ExportDocumentMetadata(),
        fallbackTitle: 'deck',
      );
      expect(_entry(odp, 'content.xml'), isNot(contains('svg:desc')));
    });
  });
}

/// De tekstinhoud van één ZIP-entry.
String _entry(Uint8List bytes, String name) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final file = archive.files.firstWhere((f) => f.name == name);
  return String.fromCharCodes(file.content as List<int>);
}
