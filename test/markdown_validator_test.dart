import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/markdown_validator.dart';

void main() {
  final service = MarkdownService();
  final validator = MarkdownValidator();

  test('valid generated deck has no errors', () {
    final markdown = service.generateDeck(
      Deck(
        title: 'Demo',
        slides: [
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Kop', bullets: ['Eerste punt']),
        ],
      ),
    );

    final result = validator.validate(markdown);
    expect(result.isValid, isTrue);
    expect(result.hasIssues, isFalse);
  });

  test('detects unclosed front matter', () {
    const markdown = '---\nmarp: true\ntheme: ocideck\n# Titel\n';

    final result = validator.validate(markdown);
    expect(result.isValid, isFalse);
    expect(
      result.issues.any(
        (issue) => issue.message.contains('Front matter is niet afgesloten'),
      ),
      isTrue,
    );
  });

  test('detects unclosed code fence', () {
    const markdown = '''
---
marp: true
---

# Code

```dart
void main() {}
''';

    final result = validator.validate(markdown);
    expect(result.isValid, isFalse);
    expect(
      result.issues.any(
        (issue) => issue.message.contains('Codeblok is niet afgesloten'),
      ),
      isTrue,
    );
  });

  test('reports an unclosed fence that swallows a following separator', () {
    // An unclosed ```dart fence runs to the end of the document, so the `---`
    // below it is code content, not a slide separator (fence-aware splitting).
    // The whole thing is therefore one slide with one still-open fence — and
    // the open/close tracker reports it even though the two ```dart lines make
    // an even count that a parity check would have read as balanced (C5).
    const markdown = '''
---
marp: true
---

# Slide een

```dart
void main() {}

---

# Slide twee

```dart
void other() {}
''';

    final result = validator.validate(markdown);
    final fenceIssues = result.issues
        .where((i) => i.message.contains('Codeblok is niet afgesloten'))
        .toList();
    expect(fenceIssues, hasLength(1));
  });

  test('detects code slide without fenced block', () {
    const markdown = '''
---
marp: true
---

<!-- _class: code -->

# Titel
print('hi');
''';

    final result = validator.validate(markdown);
    expect(result.isValid, isFalse);
    expect(
      result.issues.any(
        (issue) => issue.message.contains('broncode-slide vereist'),
      ),
      isTrue,
    );
  });

  test('detects invalid chart JSON', () {
    const markdown = '''
---
marp: true
---

<!-- _class: chart -->

```chart
{ broken json
```
''';

    final result = validator.validate(markdown);
    expect(result.isValid, isFalse);
    expect(
      result.issues.any(
        (issue) => issue.message.contains('grafiek-JSON is ongeldig'),
      ),
      isTrue,
    );
  });

  test('detects split slide with missing divs', () {
    const markdown = '''
---
marp: true
---

<!-- _class: split -->

<div class="split-text">

# Kop

</div>
''';

    final result = validator.validate(markdown);
    expect(result.isValid, isFalse);
    expect(
      result.issues.any((issue) => issue.message.contains('split-image')),
      isTrue,
    );
  });

  test('detects invalid two-bullets encoded comment', () {
    const markdown = '''
---
marp: true
---

<!-- _class: two-bullets -->
<!-- ocideck_two_bullets_left: !!! -->
<div class="ocideck-two-bullets">
<div></div>
<div></div>
</div>
''';

    final result = validator.validate(markdown);
    expect(result.isValid, isFalse);
    expect(
      result.issues.any(
        (issue) => issue.message.contains('ocideck_two_bullets_left:'),
      ),
      isTrue,
    );
  });

  test('detects table without separator row', () {
    const markdown = '''
---
marp: true
---

<!-- _class: table -->

| Kop 1 | Kop 2 |
| a | b |
''';

    final result = validator.validate(markdown);
    expect(result.isValid, isFalse);
    expect(
      result.issues.any((issue) => issue.message.contains('scheidingsrij')),
      isTrue,
    );
  });

  test('detects malformed image markdown', () {
    const markdown = '''
---
marp: true
---

![bg 50%](images/foto.png
''';

    final result = validator.validate(markdown);
    expect(result.isValid, isFalse);
    expect(
      result.issues.any(
        (issue) => issue.message.contains('afbeeldings-markdown'),
      ),
      isTrue,
    );
  });

  test('accepts valid encoded two-bullets payload', () {
    final encoded = base64Url.encode(utf8.encode(jsonEncode(['A', 'B'])));
    final markdown =
        '''
---
marp: true
---

<!-- _class: two-bullets -->
<!-- ocideck_two_bullets_left: $encoded -->
<div class="ocideck-two-bullets">
<div></div>
<div></div>
</div>
''';

    final result = validator.validate(markdown);
    expect(
      result.issues.where(
        (issue) => issue.message.contains('ocideck_two_bullets_left:'),
      ),
      isEmpty,
    );
  });

  test('flags an empty presentation', () {
    final result = validator.validate('   \n  ');
    expect(
      result.issues.any((i) => i.message.contains('De presentatie is leeg')),
      isTrue,
    );
  });

  test('flags front matter with no slides', () {
    final result = validator.validate('---\nmarp: true\ntheme: ocideck\n---\n');
    expect(
      result.issues.any((i) => i.message.contains('Geen slides gevonden')),
      isTrue,
    );
  });

  test('detects an unclosed HTML comment', () {
    const markdown = '''
---
marp: true
---

# Kop

<!-- this comment never closes
''';
    final result = validator.validate(markdown);
    expect(result.isValid, isFalse);
    expect(
      result.issues.any(
        (i) => i.message.contains('HTML-commentaar is niet afgesloten'),
      ),
      isTrue,
    );
  });

  test('accepts a multi-line HTML comment that closes on a later line', () {
    // Sprekersnotities serialiseren als een meerregelig `<!-- … -->`; de
    // openingsregel heeft op zichzelf geen `-->`, maar het commentaar sluit
    // verderop wél. Dat mag geen valse "niet afgesloten"-fout geven.
    const markdown = '''
---
marp: true
---

# Kop

<!--
Mooi verhaal
-->
''';
    final result = validator.validate(markdown);
    expect(
      result.issues.any(
        (i) => i.message.contains('HTML-commentaar is niet afgesloten'),
      ),
      isFalse,
    );
  });

  test('detects a truly unclosed multi-line HTML comment', () {
    const markdown = '''
---
marp: true
---

# Kop

<!--
Mooi verhaal dat nooit sluit
''';
    final result = validator.validate(markdown);
    expect(result.isValid, isFalse);
    expect(
      result.issues.any(
        (i) => i.message.contains('HTML-commentaar is niet afgesloten'),
      ),
      isTrue,
    );
  });

  test('detects invalid cockpit JSON', () {
    const markdown = '''
---
marp: true
---

<!-- _class: cockpit -->

```cockpit
{ broken json
```
''';
    final result = validator.validate(markdown);
    expect(
      result.issues.any((i) => i.message.contains('cockpit-JSON is ongeldig')),
      isTrue,
    );
  });

  test('detects an unclosed cockpit block', () {
    const markdown = '''
---
marp: true
---

<!-- _class: cockpit -->

```cockpit
{"instruments": []}
''';
    final result = validator.validate(markdown);
    expect(
      result.issues.any(
        (i) => i.message.contains('```cockpit-blok is niet afgesloten'),
      ),
      isTrue,
    );
  });

  test('detects a cockpit spec that is not a JSON object', () {
    const markdown = '''
---
marp: true
---

<!-- _class: cockpit -->

```cockpit
[1, 2, 3]
```
''';
    final result = validator.validate(markdown);
    expect(
      result.issues.any(
        (i) => i.message.contains('cockpit-JSON moet een object'),
      ),
      isTrue,
    );
  });

  test('detects an unclosed chart block', () {
    const markdown = '''
---
marp: true
---

<!-- _class: chart -->

```chart
{"type":"bar"}
''';
    final result = validator.validate(markdown);
    expect(
      result.issues.any(
        (i) => i.message.contains('chart-blok is niet afgesloten'),
      ),
      isTrue,
    );
  });

  test('detects an empty chart specification', () {
    const markdown = '''
---
marp: true
---

<!-- _class: chart -->

```chart
```
''';
    final result = validator.validate(markdown);
    expect(
      result.issues.any(
        (i) => i.message.contains('grafiek-specificatie is leeg'),
      ),
      isTrue,
    );
  });

  test('detects a table slide without a table', () {
    const markdown = '''
---
marp: true
---

<!-- _class: table -->

# Geen tabel hier
''';
    final result = validator.validate(markdown);
    expect(
      result.issues.any(
        (i) => i.message.contains('tabel-slide bevat geen tabel'),
      ),
      isTrue,
    );
  });

  // Branches the mutation check (`make mutate`) flagged as untested: the
  // slide-level comment-key validators and the <video>/<audio> tag guards.
  // Each test forces one predicate to matter, so a mutant that neutralises it
  // is killed instead of surviving.
  group('slide-level comment and media-tag validation', () {
    test('flags an unknown slide-level TLP comment', () {
      const md = '---\nmarp: true\n---\n\n# Slide\n\n<!-- tlp: bogus -->\n';
      final result = validator.validate(md);
      expect(
        result.issues.any((i) => i.message.contains('onbekend TLP-niveau')),
        isTrue,
      );
    });

    test('flags a non-numeric advance comment', () {
      const md = '---\nmarp: true\n---\n\n# Slide\n\n<!-- advance: abc -->\n';
      final result = validator.validate(md);
      expect(
        result.issues.any((i) => i.message.contains('advance-waarde')),
        isTrue,
      );
    });

    test('flags Infinity/NaN advance values as non-numeric', () {
      for (final v in ['Infinity', '-Infinity', 'NaN', '1e400']) {
        final md = '---\nmarp: true\n---\n\n# Slide\n\n<!-- advance: $v -->\n';
        final result = validator.validate(md);
        expect(
          result.issues.any((i) => i.message.contains('advance-waarde')),
          isTrue,
          reason: 'advance: $v should be rejected',
        );
      }
    });

    test('flags an unknown list-style comment', () {
      const md =
          '---\nmarp: true\n---\n\n# Slide\n\n<!-- ocideck_list_style: bogus -->\n';
      final result = validator.validate(md);
      expect(
        result.issues.any((i) => i.message.contains('onbekende lijststijl')),
        isTrue,
      );
    });

    test('flags an unterminated <video> tag', () {
      const md = '---\nmarp: true\n---\n\n# Slide\n\n<video src="clip.mp4"\n';
      final result = validator.validate(md);
      expect(
        result.issues.any(
          (i) => i.message.contains('`<video>`-tag is onvolledig'),
        ),
        isTrue,
      );
    });

    test('accepts a complete <video> tag without an incomplete-tag error', () {
      const md =
          '---\nmarp: true\n---\n\n# Slide\n\n<video src="clip.mp4" controls></video>\n';
      final result = validator.validate(md);
      expect(
        result.issues.any(
          (i) => i.message.contains('`<video>`-tag is onvolledig'),
        ),
        isFalse,
      );
    });

    test('flags a <video> tag missing a src attribute', () {
      const md =
          '---\nmarp: true\n---\n\n# Slide\n\n<video controls></video>\n';
      final result = validator.validate(md);
      expect(
        result.issues.any((i) => i.message.contains('mist een `src')),
        isTrue,
      );
    });

    test('flags an unterminated <audio> tag', () {
      const md = '---\nmarp: true\n---\n\n# Slide\n\n<audio src="a.mp3"\n';
      final result = validator.validate(md);
      expect(
        result.issues.any(
          (i) => i.message.contains('`<audio>`-tag is onvolledig'),
        ),
        isTrue,
      );
    });

    test('accepts a complete <audio> tag without an incomplete-tag error', () {
      const md =
          '---\nmarp: true\n---\n\n# Slide\n\n<audio src="a.mp3" controls></audio>\n';
      final result = validator.validate(md);
      expect(
        result.issues.any(
          (i) => i.message.contains('`<audio>`-tag is onvolledig'),
        ),
        isFalse,
      );
    });

    test('does not warn about a # comment line in the front matter', () {
      const md =
          '---\nmarp: true\n# een commentaar\ntheme: ocideck\n---\n\n# Slide\n';
      final result = validator.validate(md);
      expect(
        result.issues.any(
          (i) => i.message.contains('geen sleutel:waarde-vorm'),
        ),
        isFalse,
      );
    });
  });

  group('hardening: CRLF, fence-awareness, unknown keys/directives', () {
    test('normalises CRLF before validating unclosed front matter', () {
      // With Windows line endings the raw `lines.first` is "---\r"; without
      // normalisation the front-matter probe (and every downstream check) is
      // silently skipped while the parser still succeeds.
      const md = '---\r\ntitle: X\r\n\r\n# Slide een\r\n';
      final result = validator.validate(md);
      expect(
        result.issues.any((i) => i.message.contains('niet afgesloten')),
        isTrue,
      );
    });

    test('a valid CRLF deck reports no false errors', () {
      final lf = service.generateDeck(
        Deck(
          title: 'Demo',
          slides: [
            Slide.create(
              SlideType.bullets,
            ).copyWith(title: 'Kop', bullets: ['Eerste punt']),
          ],
        ),
      );
      final crlf = lf.replaceAll('\n', '\r\n');
      expect(validator.validate(crlf).isValid, isTrue);
      expect(validator.validate(crlf).warningCount, 0);
    });

    test('a `---` inside a fenced code block does not split the slide', () {
      const md = '---\nmarp: true\n---\n\n# Een\n\n```\nvoor\n---\nna\n```\n';
      final result = validator.validate(md);
      // One slide, one closed fence: no unclosed-fence and no "no slides" error.
      expect(result.issues.any((i) => i.message.contains('Codeblok')), isFalse);
      expect(service.parseDeck(md)!.slides, hasLength(1));
    });

    test('warns on an unknown front-matter key', () {
      const md = '---\nmarp: true\npagenate: false\n---\n\n# Slide\n';
      final result = validator.validate(md);
      expect(
        result.issues.any(
          (i) =>
              i.severity == MarkdownValidationSeverity.warning &&
              i.message.contains('pagenate'),
        ),
        isTrue,
      );
    });

    test('does not warn on known / Marp front-matter keys', () {
      const md =
          '---\nmarp: true\ntheme: ocideck\ntitle: X\nauthor: A\n---\n\n# Slide\n';
      expect(validator.validate(md).warningCount, 0);
    });

    test('does not warn on front-matter keys the parser actually reads', () {
      // Regressie: deze zeven sleutels worden door `markdown_service_parse`
      // verwerkt, maar ontbraken in de whitelist van de checker. Die meldde ze
      // als "wordt genegeerd" terwijl ze juist effect hebben.
      const md =
          '---\nmarp: true\n'
          'language: nl\n'
          'tool: Burp Suite@2026.1\n'
          'standards: WSTG, MASTG\n'
          'privacy: redact\n'
          'ocideck_seal_tsr: MIICxDCCAaw=\n'
          'ocideck_miauw_waivers: e30=\n'
          'ocideck_miauw_confirmations: e30=\n'
          '---\n\n# Slide\n';
      final result = validator.validate(md);
      expect(
        result.issues.where(
          (i) => i.message.contains('Onbekende front-matter'),
        ),
        isEmpty,
        reason: 'de parser leest deze sleutels, dus de checker mag niet klagen',
      );
    });

    test('does not warn on the checklist-scope directive', () {
      const md =
          '---\nmarp: true\n---\n\n<!-- _class: checklist -->\n'
          '<!-- ocideck_checklist_scope: https://app.example/login -->\n\n'
          '# Checklist\n';
      final result = validator.validate(md);
      expect(
        result.issues.any((i) => i.message.contains('ocideck_checklist_scope')),
        isFalse,
      );
    });

    test('warns on an unsupported scoped Marp directive', () {
      const md =
          '---\nmarp: true\n---\n\n<!-- _paginate: false -->\n\n# Slide\n';
      final result = validator.validate(md);
      expect(
        result.issues.any(
          (i) =>
              i.severity == MarkdownValidationSeverity.warning &&
              i.message.contains('_paginate'),
        ),
        isTrue,
      );
    });

    test('does not warn on supported directives or prose notes', () {
      const md =
          '---\nmarp: true\n---\n\n<!-- _class: title -->\n'
          '<!-- ocideck_bullet_marker: paw -->\n\n# Slide\n\n'
          '<!-- Vergeet niet te lachen -->\n<!-- TODO: dit later fixen -->\n';
      final result = validator.validate(md);
      expect(
        result.issues.any((i) => i.message.contains('niet ondersteund')),
        isFalse,
      );
    });

    test('a <div> inside a code fence does not break div balance', () {
      const md =
          '---\nmarp: true\n---\n\n<!-- _class: code -->\n\n# HTML\n\n'
          '```html\n<div class="x">\n```\n';
      final result = validator.validate(md);
      expect(result.issues.any((i) => i.message.contains('div')), isFalse);
    });

    test('an unclosed image inside a code fence is not flagged', () {
      const md =
          '---\nmarp: true\n---\n\n<!-- _class: code -->\n\n# Voorbeeld\n\n'
          '```dart\nfinal s = "![a](b";\n```\n';
      final result = validator.validate(md);
      expect(
        result.issues.any((i) => i.message.contains('afbeeldings-markdown')),
        isFalse,
      );
    });

    test('detects an unclosed tilde (~~~) fence', () {
      const md = '---\nmarp: true\n---\n\n# Code\n\n~~~\nvoid main() {}\n';
      final result = validator.validate(md);
      expect(
        result.issues.any((i) => i.message.contains('Codeblok is niet')),
        isTrue,
      );
    });

    test('a <div> inside a tilde (~~~) fence does not break div balance', () {
      const md =
          '---\nmarp: true\n---\n\n# HTML\n\n~~~html\n<div class="x">\n~~~\n';
      final result = validator.validate(md);
      expect(result.issues.any((i) => i.message.contains('div')), isFalse);
    });
  });
}
