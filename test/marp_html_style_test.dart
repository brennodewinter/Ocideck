import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/marp_html_service.dart';

Future<String> _diskLoader(String asset) => File(asset).readAsString();

void main() {
  final service = MarpHtmlService(loadAsset: _diskLoader);

  test('HTML export applies inherited and slide-local Marp styles', () async {
    const markdown = '''
---
marp: true
color: '#112233'
backgroundColor: '#fefefe'
backgroundImage: "linear-gradient(#0008, #0008)"
header: '**Deckkop**'
footer: 'Deck *voet*'
---

# Eerste

---

<!-- _color: #abcdef -->
<!-- _backgroundColor: #101010 -->
<!-- _backgroundImage: linear-gradient(#123, #456) -->
<!-- _header: *Diakop* -->
<!-- _footer: Diavoet -->

# Tweede
''';

    final html = await service.build(markdown);

    expect(
      html,
      contains(
        'class="slide" '
        'style="color:#112233;background-color:#fefefe;'
        'background-image:linear-gradient(#0008, #0008)"',
      ),
    );
    expect(
      html,
      contains(
        'class="slide" '
        'style="color:#abcdef;background-color:#101010;'
        'background-image:linear-gradient(#123, #456)"',
      ),
    );
    expect(
      html,
      contains(
        '<span hidden class="marp-header-source" '
        'data-markdown="**Deckkop**"></span>',
      ),
    );
    expect(
      html,
      contains(
        '<span hidden class="marp-footer-source" '
        'data-markdown="Deck *voet*"></span>',
      ),
    );
    expect(html, contains('data-markdown="*Diakop*"'));
    expect(html, contains('data-markdown="Diavoet"'));
    expect(html, contains('marked.parseInline(markdown)'));
  });

  test(
    'HTML export renders fit, contain and safe Marp image filters',
    () async {
      const markdown = '''
---
marp: true
---

![bg contain blur:2px brightness:1.2 grayscale](images/bg.png)

# Een erg lange kop die passend hoort te worden
<!-- fit -->
''';

      final html = await service.build(markdown);

      expect(html, contains('marp-heading-fit'));
      expect(html, contains('data-marp-bg-fit="contain"'));
      expect(
        html,
        contains(
          'data-marp-bg-filter="blur(2px) brightness(1.2) grayscale(1)"',
        ),
      );
      expect(html, contains('fitMarpHeading'));
      expect(html, contains("img.style.objectFit='contain'"));
      expect(html, contains('img.style.filter=sec.dataset.marpBgFilter'));
    },
  );

  test('HTML export ignores unsafe CSS directive values', () async {
    const markdown = '''
---
marp: true
color: 'red;position:fixed'
backgroundColor: '<script>'
backgroundImage: 'url(https://example.invalid/beacon.png)'
---

# Veilig
''';

    final html = await service.build(markdown);

    expect(html, isNot(contains('style="color:red;position:fixed')));
    expect(html, isNot(contains('background-color:&lt;script>')));
    expect(html, isNot(contains('background-image:url(https://')));
  });

  test('HTML and Flutter share the same normalized colour subset', () async {
    const markdown = '''
---
marp: true
color: red
backgroundColor: 'rgb(1, 2, 3)'
---

# Veilig
''';

    final html = await service.build(markdown);

    expect(html, contains('style="color:#ff0000"'));
    expect(html, isNot(contains('background-color:rgb')));
  });

  test('HTML applies no more than 32 image filters', () async {
    final filters = List.generate(40, (i) => 'brightness:${i + 1}').join(' ');
    final html = await service.build(
      '# Begrensd\n\n![bg $filters](images/bg.png)',
    );
    final attribute = RegExp(
      r'data-marp-bg-filter="([^"]+)"',
    ).firstMatch(html)!.group(1)!;

    expect(RegExp(r'brightness\(').allMatches(attribute), hasLength(32));
    expect(attribute, isNot(contains('brightness(33)')));
  });

  test('deck header and footer are represented once for many slides', () async {
    final slides = List.generate(80, (i) => '# Dia $i').join('\n\n---\n\n');
    final html = await service.build('''
---
marp: true
header: '**Een forse gedeelde kop**'
footer: 'Een forse gedeelde voet'
---

$slides
''');

    expect(
      RegExp(r'\*\*Een forse gedeelde kop\*\*').allMatches(html),
      hasLength(1),
    );
    expect(RegExp('Een forse gedeelde voet').allMatches(html), hasLength(1));
    expect(
      html,
      contains("document.querySelector('main > .marp-'+position+'-source')"),
    );
  });

  test('HTML export expands supported emoji shortcodes offline', () async {
    final html = await service.build('# Lancering :rocket: :white_check_mark:');

    expect(html, contains('# Lancering 🚀 ✅'));
    expect(html, isNot(contains(':rocket:')));
    expect(html, isNot(contains(':white_check_mark:')));
    expect(html, isNot(contains('twemoji')));
  });

  test('HTML export embeds explicit Marp backgroundImage locally', () async {
    final html = await service.build(
      '''---
marp: true
backgroundImage: "url('images/bg.png')"
---

# Lokaal
''',
      embedImage: (source) async =>
          source == 'images/bg.png' ? 'data:image/png;base64,AA==' : null,
    );

    expect(html, contains('background-image:url(#ocideck-img-0)'));
    expect(html, contains('data:image/png;base64,AA=='));
    expect(html, contains("sec.style.backgroundImage='url(\"'+bgUri+'\")'"));
    expect(html, isNot(contains('images/bg.png')));
  });
}
