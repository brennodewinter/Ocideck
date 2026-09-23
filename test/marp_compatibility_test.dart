import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/marp_compatibility.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/marp_compatibility.dart';

void main() {
  final checker = MarpCompatibility();

  const cleanDeck = '''
---
marp: true
theme: default
paginate: true
---

# Eerste dia

- een
- twee

---

## Tweede dia

Tekst.
''';

  MarpCompatStatus statusOf(
    String markdown, {
    MarpCompatContext context = MarpCompatContext.project,
    bool deckScope = true,
  }) => checker
      .check(markdown, context: context, deckScope: deckScope)
      .status;

  int warningsOf(
    String markdown, {
    MarpCompatContext context = MarpCompatContext.project,
  }) => checker.check(markdown, context: context).warningCount;

  group('status: compatible', () {
    test('een zuiver Marp-deck is groen', () {
      expect(statusOf(cleanDeck), MarpCompatStatus.compatible);
    });

    test('bare Marpit-directives (paginate, _footer) geven geen bevinding', () {
      const md = '''
---
marp: true
---

paginate: true

# Dia

<!-- _footer: alleen deze -->
''';
      final report = checker.check(md);
      expect(report.status, MarpCompatStatus.compatible);
      expect(report.findings, isEmpty);
    });

    test('ocideck-sleutels en -comments zijn hooguit info', () {
      const md = '''
---
marp: true
tlp: amber
timing: pechakucha
ocideck_target_seconds: 300
---

# Dia

<!-- advance: 30 -->
<!-- ocideck_detail -->
''';
      final report = checker.check(md);
      expect(report.status, MarpCompatStatus.compatible);
      expect(report.warningCount, 0);
      expect(report.findings, isNotEmpty); // info-bevindingen staan er wél
    });

    test('CRLF-regelafbrekingen normaliseren als de parser', () {
      expect(
        statusOf(cleanDeck.replaceAll('\n', '\r\n')),
        MarpCompatStatus.compatible,
      );
    });
  });

  group('status: incompatible', () {
    test('geen front matter = geen Marp', () {
      expect(statusOf('# Gewone tekst\n\nGeen slides.'), 
          MarpCompatStatus.incompatible);
    });

    test('marp: true ontbreekt', () {
      const md = '''
---
theme: default
---

# Dia
''';
      expect(statusOf(md), MarpCompatStatus.incompatible);
    });

    test('marp: false schakelt Marp uit', () {
      const md = '''
---
marp: false
---

# Dia
''';
      expect(statusOf(md), MarpCompatStatus.incompatible);
    });

    test('niet-afgesloten front matter', () {
      const md = '''
---
marp: true
theme: default
''';
      expect(statusOf(md), MarpCompatStatus.incompatible);
    });

    test('dubbele sleutel in front matter', () {
      const md = '''
---
marp: true
theme: default
theme: gaia
---

# Dia
''';
      expect(statusOf(md), MarpCompatStatus.incompatible);
    });

    test('tab in front matter', () {
      expect(
        statusOf('---\nmarp: true\ntheme:\tdefault\n---\n\n# Dia\n'),
        MarpCompatStatus.incompatible,
      );
    });

    test('onafgesloten quote', () {
      const md = '''
---
marp: true
title: "Ongesloten
---

# Dia
''';
      expect(statusOf(md), MarpCompatStatus.incompatible);
    });

    test('YAML-sigil als waarde', () {
      const md = '''
---
marp: true
title: *anker
---

# Dia
''';
      expect(statusOf(md), MarpCompatStatus.incompatible);
    });
  });

  group('status: degraded', () {
    test('chart-fence rendert als codeblok', () {
      const md = '''
---
marp: true
---

<!-- _class: chart -->

```chart
{"kind":"bar"}
```
''';
      expect(warningsOf(md), greaterThanOrEqualTo(2)); // class + fence
      expect(statusOf(md), MarpCompatStatus.degraded);
    });

    test('OciDeck-slidetype-class degradeert', () {
      const md = '''
---
marp: true
---

<!-- _class: timeline -->

2020|Begin
''';
      expect(statusOf(md), MarpCompatStatus.degraded);
    });

    test('pure CSS-classes geven geen bevinding', () {
      const md = '''
---
marp: true
---

<!-- _class: title split logo-safe -->

# Titel
''';
      expect(statusOf(md), MarpCompatStatus.compatible);
    });

    test('skip-dia toont gewoon in Marp', () {
      const md = '''
---
marp: true
---

<!-- skip -->

# Verborgen in OciDeck
''';
      expect(statusOf(md), MarpCompatStatus.degraded);
    });

    test('tlp-holdback valt weg', () {
      const md = '''
---
marp: true
---

<!-- tlp: red -->

# Intern
''';
      expect(statusOf(md), MarpCompatStatus.degraded);
    });

    test('onbekend thema alleen als los bestand een warning', () {
      const md = '''
---
marp: true
theme: mijn-thema
---

# Dia
''';
      expect(
        statusOf(md, context: MarpCompatContext.bareFile),
        MarpCompatStatus.degraded,
      );
      expect(statusOf(md), MarpCompatStatus.compatible);
    });

    test('headingDivider waarschuwt', () {
      const md = '''
---
marp: true
headingDivider: 2
---

# Dia
''';
      expect(statusOf(md), MarpCompatStatus.degraded);
    });

    test('mem:-media alleen als los bestand een warning', () {
      const md = '''
---
marp: true
---

![foto](mem:42)
''';
      expect(
        statusOf(md, context: MarpCompatContext.bareFile),
        MarpCompatStatus.degraded,
      );
      expect(statusOf(md), MarpCompatStatus.compatible);
    });

    test('absoluut mediapad waarschuwt', () {
      const md = '''
---
marp: true
---

![foto](/Users/ik/foto.png)
''';
      expect(statusOf(md), MarpCompatStatus.degraded);
    });

    test('--- direct onder tekst is dubbelzinnig', () {
      const md = '''
---
marp: true
---

Tekst direct boven de streep
---

# Volgende dia
''';
      expect(statusOf(md), MarpCompatStatus.degraded);
    });

    test('--- na lege regel is zuiver', () {
      const md = '''
---
marp: true
---

Tekst met lege regel

---

# Volgende dia
''';
      expect(statusOf(md), MarpCompatStatus.compatible);
    });

    test('--- onder commentaar of kop is geen setext', () {
      const md = '''
---
marp: true
---

<!-- _class: title -->
---

# Kop
---

- lijstitem
---

# Einde
''';
      expect(statusOf(md), MarpCompatStatus.compatible);
    });
  });

  group('acceptatievlag', () {
    const degradedDeck = '''
---
marp: true
---

<!-- _class: chart -->

```chart
{}
```
''';

    test('warnings + vlag = geaccepteerd', () {
      const md = '''
---
marp: true
ocideck_marp_compat_accepted: true
---

<!-- _class: chart -->

```chart
{}
```
''';
      final report = checker.check(md);
      expect(report.status, MarpCompatStatus.accepted);
      expect(report.accepted, isTrue);
      // De bevindingen blijven bestaan — geaccepteerd is niet verdwenen.
      expect(report.warningCount, greaterThan(0));
    });

    test('fouten blijven rood ook met vlag', () {
      const md = '''
---
marp: false
ocideck_marp_compat_accepted: true
---

# Dia
''';
      expect(statusOf(md), MarpCompatStatus.incompatible);
    });

    test('vlag zonder warnings blijft groen', () {
      const md = '''
---
marp: true
ocideck_marp_compat_accepted: true
---

# Dia
''';
      expect(statusOf(md), MarpCompatStatus.compatible);
    });

    test('zonder vlag is dezelfde bron oranje', () {
      expect(statusOf(degradedDeck), MarpCompatStatus.degraded);
    });
  });

  group('scope', () {
    test('slide-scope eist geen front matter', () {
      expect(
        statusOf('# Dia\n\n- bullets\n', deckScope: false),
        MarpCompatStatus.compatible,
      );
    });

    test('slide-scope ziet nog steeds degradaties', () {
      expect(
        statusOf('<!-- skip -->\n\n# Dia\n', deckScope: false),
        MarpCompatStatus.degraded,
      );
    });
  });

  group('eigen schrijfwijze', () {
    test('een door generateDeck geproduceerd deck geeft geen vals alarm', () {
      final markdown = MarkdownService().generateDeck(
        Deck(
          title: 'Demo',
          slides: [
            Slide.create(SlideType.title).copyWith(title: 'Demo'),
            Slide.create(
              SlideType.bullets,
            ).copyWith(title: 'Punten', bullets: const ['een', 'twee']),
            Slide.create(
              SlideType.table,
            ).copyWith(title: 'Tabel', tableRows: const [['a', 'b']]),
          ],
        ),
      );
      // In projectcontext (waar het thema naast het bestand ligt) moet eigen
      // output zonder hand-edits groen zijn — info-bevindingen mogen.
      final report = checker.check(markdown);
      expect(report.status, MarpCompatStatus.compatible);
      expect(report.errorCount, 0);
      expect(report.warningCount, 0);
    });
  });

  group('findings-kwaliteit', () {
    test('elke bevinding heeft een regelnummer voor jump-to-line', () {
      const md = '''
---
marp: true
---

<!-- skip -->

# Dia

```chart
{}
```
''';
      final report = checker.check(md);
      for (final finding in report.findings) {
        expect(finding.line, greaterThan(0));
      }
      expect(report.findings, isNotEmpty);
    });

    test('commentaar in een codeblok is een voorbeeld, geen bevinding', () {
      const md = '''
---
marp: true
---

```markdown
<!-- skip -->
```
''';
      expect(warningsOf(md), 0);
    });
  });
}
