import 'package:material_ui/material_ui.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/rich_text_layout.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Widget _host(Slide slide, {int richTextPage = 0}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox(
        width: 800,
        height: 450,
        child: SlidePreviewWidget(slide: slide, richTextPage: richTextPage),
      ),
    ),
  );
}

/// De markdown uit issue #1409: een `_class`-commentaarregel plus een lang
/// yaml-codeblok dat voorheen de hele dia door `FittedBox(scaleDown)` naar
/// ~56 % kromtrok, en waarbij het commentaar als zichtbare tekst verscheen.
const _issue1409Markdown = r'''<!-- _class: logo-safe -->

# Installing Forgejo server

$ ansible-galaxy collection install forgejo.forgejo

```yaml
- name: 'Install Forgejo'
  hosts: all
  roles:
    - role: forgejo.forgejo.forgejo
  vars:
    # Assume reverse proxy usage redirecting to localhost:3000
    forgejo_fqdn: 'forgejo.domain.tld'
    forgejo_root_url: 'http://forgejo.domain.tld'
    forgejo_protocol: http
    forgejo_user: git
    forgejo_ssh_port: 22
    forgejo_start_ssh: false # Do not start Forgejo SSH server
    forgejo_version: "15.0.1" # or "latest"
```

$ ansible-playbook -i <ip>, install-forgejo.yml -u userid -K -b

(Also see: https://oneuptime.com/blog/post/2026-02-21-ansible-configure-nginx-reverse-proxy)
''';

void main() {
  testWidgets('free Markdown renders a highlighted code block', (tester) async {
    final slide = Slide.create(SlideType.freeMarkdown).copyWith(
      customMarkdown: '# Demo\n\n```dart\nvoid main() => print(42);\n```\n',
    );
    await tester.pumpWidget(_host(slide));

    expect(find.byKey(const Key('highlighted_code')), findsOneWidget);
  });

  testWidgets('free Markdown renders display math', (tester) async {
    final slide = Slide.create(
      SlideType.freeMarkdown,
    ).copyWith(customMarkdown: 'Stelling:\n\n\$\$E = mc^2\$\$\n');
    await tester.pumpWidget(_host(slide));

    expect(find.byType(Math), findsOneWidget);
  });

  testWidgets('an unknown code language falls back without throwing', (
    tester,
  ) async {
    final slide = Slide.create(
      SlideType.freeMarkdown,
    ).copyWith(customMarkdown: '```nonexistentlang\nsome code\n```\n');
    await tester.pumpWidget(_host(slide));

    // No highlighted code (unknown language) and no exception during build.
    expect(find.byKey(const Key('highlighted_code')), findsNothing);
    expect(tester.takeException(), isNull);
    expect(find.text('some code'), findsOneWidget);
  });

  testWidgets('#1409: HTML-commentaarregel wordt niet als tekst getekend', (
    tester,
  ) async {
    final slide = Slide.create(
      SlideType.freeMarkdown,
    ).copyWith(customMarkdown: _issue1409Markdown);
    await tester.pumpWidget(_host(slide));

    expect(
      find.textContaining('<!-- _class'),
      findsNothing,
      reason: 'een HTML-commentaar hoort niet als lopende tekst op de dia',
    );
  });

  testWidgets(
    '#1409: een te lange body pagineert in plaats van alles te krimpen',
    (tester) async {
      const profile = ThemeProfile();
      final slide = Slide.create(
        SlideType.freeMarkdown,
      ).copyWith(customMarkdown: _issue1409Markdown);

      // Voorheen één pagina met FittedBox-scaleDown; nu meerdere pagina's omdat
      // de body niet op één 16:9-frame past op leesbare grootte.
      final pages = richTextPageCountForSlide(
        slide: slide,
        profile: profile,
        splitWithImage: false,
      );
      expect(pages, greaterThan(1), reason: 'de issue-body hoort te pagineren');

      // Het yaml-codeblok mag niet verloren gaan: het staat op precies één pagina.
      var pagesWithCode = 0;
      for (var p = 0; p < pages; p++) {
        await tester.pumpWidget(_host(slide, richTextPage: p));
        if (find.byKey(const Key('highlighted_code')).evaluate().isNotEmpty) {
          pagesWithCode++;
        }
      }
      expect(
        pagesWithCode,
        1,
        reason: 'het codeblok hoort op één pagina, niet op nul of op allemaal',
      );
    },
  );
}
