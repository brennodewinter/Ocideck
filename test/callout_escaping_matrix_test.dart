// Escaping-matrix test for image callouts (IMAGE_CALLOUTS.md §9 acceptance gate).
//
// One description carrying every hostile character the design names — `"`, `'`,
// `#`, `:`, `<`, `&`, `</script>`, `\`, `{`, `}`, `%`, `$`, `_`, `^`, `~` and a
// newline — is driven through all four writer boundaries. Each writer must prove
// it escapes at its own boundary; none may rely on an earlier one having done it.
//
// The four boundaries (§9):
//   1. markdownYamlScalar — for the front-matter block (public function)
//   2. MarpHtmlService._htmlText — tested via renderImageCallouts (hidden desc span)
//   3. MarpHtmlService._htmlAttr — tested via renderImageCallouts (aria-label)
//   4. _escapeLatex — tested via buildBeamerBody (TikZ nodes, caption)
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/latex/beamer_slide_builder.dart';
import 'package:ocideck/services/markdown_front_matter_codec.dart';
import 'package:ocideck/services/marp_html_service.dart';

/// The hostile description from §9 — every character that can break a writer.
const _hostile =
    r'''has "quotes" 'apos' #hash :colon <angle> &amp </script> '''
    r'\backslash {brace} %pct $dollar _under ^caret ~tilde'
    ''
    '\nand a newline';

/// A slide with a callout carrying the hostile description, ready for rendering.
Slide _hostileSlide() => Slide.create(SlideType.bulletsImage).copyWith(
  anchor: 's1',
  title: 'T',
  imagePath: 'photo.png',
  callouts: [
    ImageCallout(
      reference: 'A',
      targets: const [CalloutPoint(0.4, 0.2)],
      description: _hostile,
    ),
  ],
);

const _splitBody =
    '<div class="split-image">\n![](photo.png)\n</div>\n'
    '- bullet (A)\n';

void main() {
  group('callout escaping matrix — §9 acceptance gate', () {
    // ── 1. markdownYamlScalar (front-matter block) ──────────────────────────
    group('1. markdownYamlScalar (front-matter block)', () {
      test('hostile description is quoted and escaped for YAML', () {
        final scalar = markdownYamlScalar(_hostile);
        expect(scalar.startsWith('"'), isTrue);
        expect(scalar.endsWith('"'), isTrue);
        expect(scalar.contains(r'\"'), isTrue);
        expect(scalar.contains(r'\\'), isTrue);
        expect(scalar.contains(r'\n'), isTrue);
        expect(scalar.contains('\n'), isFalse);
      });

      test('hostile description survives a YAML scalar round-trip', () {
        final scalar = markdownYamlScalar(_hostile);
        expect(parseMarkdownYamlScalar(scalar), _hostile);
      });
    });

    // ── 2. HTML text content (via renderImageCallouts hidden desc span) ─────
    group('2. HTML text content (hidden description span)', () {
      test('hostile description in hidden desc span is text-escaped', () {
        final result = renderImageCallouts(_splitBody, _hostileSlide());
        expect(result, contains('ocideck-callout-desc'));
        // < and > must be escaped — no raw </script>.
        expect(result, isNot(contains('</script>')));
        expect(result, contains('&lt;angle&gt;'));
        // & must be escaped.
        expect(result, contains('&amp;'));
      });
    });

    // ── 3. HTML attribute (via renderImageCallouts aria-label) ──────────────
    group('3. HTML attribute (aria-label)', () {
      test(
        'aria-label with hostile description cannot break out of attribute',
        () {
          final result = renderImageCallouts(_splitBody, _hostileSlide());
          // Extract every aria-label="..." value and verify no raw " inside.
          final ariaMatches = RegExp(
            r'aria-label="([^"]*)"',
          ).allMatches(result);
          expect(ariaMatches, isNotEmpty);
          for (final m in ariaMatches) {
            final val = m.group(1)!;
            expect(val.contains('"'), isFalse, reason: 'raw " in aria-label');
            expect(val.contains('</script>'), isFalse);
            expect(val.contains('<'), isFalse, reason: 'raw < in aria-label');
          }
        },
      );
    });

    // ── 4. LaTeX (via buildBeamerBody) ──────────────────────────────────────
    group('4. LaTeX (TikZ nodes)', () {
      test('hostile description does NOT appear raw in LaTeX output', () {
        // The callout description is never placed in TikZ — only the
        // reference letter (which is [A-Z] only) goes into a \node. This
        // is safe by construction: the description cannot break LaTeX
        // because it never reaches LaTeX. Verify that.
        final deck = Deck(title: 't', slides: [_hostileSlide()]);
        final latex = buildBeamerBody(deck);
        // The hostile description must not appear raw in the LaTeX output.
        expect(latex, isNot(contains('</script>')));
        expect(latex, isNot(contains(r'$dollar')));
        expect(latex, isNot(contains(r'\backslash')));
      });

      test('callout reference in TikZ node is valid LaTeX', () {
        final deck = Deck(title: 't', slides: [_hostileSlide()]);
        final latex = buildBeamerBody(deck);
        expect(latex, contains(r'\node'));
        expect(latex, contains('{A}'));
      });

      test('LaTeX metacharacters in title are escaped', () {
        // The title goes through _escapeLatex. Verify the escaping works
        // for the LaTeX boundary independently.
        final slide = Slide.create(SlideType.bulletsImage).copyWith(
          anchor: 's1',
          title: r'a&b%c#d_e{f}g~h^i',
          imagePath: 'photo.png',
          callouts: const [
            ImageCallout(reference: 'A', targets: [CalloutPoint(0.4, 0.2)]),
          ],
        );
        final deck = Deck(title: 't', slides: [slide]);
        final latex = buildBeamerBody(deck);
        // _escapeLatex escapes: \ & % # _ { } ~ ^
        expect(latex, contains(r'\&'));
        expect(latex, contains(r'\%'));
        expect(latex, contains(r'\#'));
        expect(latex, contains(r'\_'));
        expect(latex, contains(r'\{'));
        expect(latex, contains(r'\}'));
        // No HTML entities in LaTeX.
        expect(latex, isNot(contains('&amp;')));
      });
    });

    // ── Cross-boundary independence ─────────────────────────────────────────
    group('cross-boundary independence', () {
      test('YAML and HTML escaping use different escape sequences', () {
        final yamlOut = markdownYamlScalar(_hostile);
        final htmlOut = renderImageCallouts(_splitBody, _hostileSlide());
        // YAML uses \" for quotes.
        expect(yamlOut, contains(r'\"'));
        // HTML uses &lt; / &gt; / &amp;.
        expect(htmlOut, contains('&lt;'));
        expect(htmlOut, contains('&amp;'));
        // YAML does not use HTML entities.
        expect(yamlOut, isNot(contains('&lt;')));
        // HTML does not use YAML \".
        expect(htmlOut, isNot(contains(r'\"')));
      });

      test('HTML text and attribute escaping differ on double-quote', () {
        final result = renderImageCallouts(_splitBody, _hostileSlide());
        // The aria-label (attribute) has &quot; for double quotes.
        expect(result, contains('&quot;'));
        // The hidden desc span (text content) does NOT escape " — _htmlText
        // only escapes & < >. The " survives as literal text, which is safe
        // in text content but would break an attribute. This proves the two
        // boundaries use different escaping.
        final descSpanMatch = RegExp(
          r'<span class="ocideck-callout-desc"[^>]*>(.*?)</span>',
          dotAll: true,
        ).firstMatch(result);
        expect(descSpanMatch, isNotNull);
        final descContent = descSpanMatch!.group(1)!;
        // The " from the hostile string should be a literal " in text content.
        expect(
          descContent.contains('&quot;'),
          isFalse,
          reason: '_htmlText should not escape " — that is _htmlAttr\'s job',
        );
      });

      test('LaTeX escaping is independent from HTML and YAML', () {
        final slide = Slide.create(SlideType.bulletsImage).copyWith(
          anchor: 's1',
          title: r'a&b%c#d',
          imagePath: 'p.png',
          callouts: const [
            ImageCallout(reference: 'A', targets: [CalloutPoint(0.4, 0.2)]),
          ],
        );
        final deck = Deck(title: 't', slides: [slide]);
        final latex = buildBeamerBody(deck);
        // LaTeX uses \& \% \# — not HTML entities or YAML quoting.
        expect(latex, contains(r'\&'));
        expect(latex, contains(r'\%'));
        expect(latex, contains(r'\#'));
        expect(latex, isNot(contains('&amp;')));
      });
    });
  });
}
