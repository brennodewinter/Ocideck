import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/utils/document_front_matter.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('splitDocumentFrontMatter', () {
    test('plain body → no block', () {
      const src = '# Titel\n\nTekst.';
      final s = splitDocumentFrontMatter(src);
      expect(s.block, '');
      expect(s.body, src);
    });

    test(
      'leading --- without a closing fence is a horizontal rule, not fm',
      () {
        const src = '---\n\nEen scheidingslijn, geen front matter.';
        final s = splitDocumentFrontMatter(src);
        expect(s.block, '');
        expect(s.body, src);
      },
    );

    test(
      'valid block splits off, trailing blank line folded into the block',
      () {
        const src = '---\ntheme: Europa\n---\n\n# Titel\n\nTekst.';
        final s = splitDocumentFrontMatter(src);
        expect(s.block, '---\ntheme: Europa\n---\n\n');
        expect(s.body, '# Titel\n\nTekst.');
        expect(s.block + s.body, src);
      },
    );

    test('a --- heading --- is two rules, not front matter', () {
      const src = '---\n# Kop\n---\n\nTekst.';
      final s = splitDocumentFrontMatter(src);
      expect(s.block, '');
      expect(s.body, src);
    });

    test('a leading --- page break with a later --- stays in the body', () {
      // De reden voor de verharding: een pagina-einde bovenaan mag geen
      // frontmatter-blok worden zodra er verderop nóg een --- staat.
      const src = '---\n\n# Eerste\n\n---\n\n# Tweede\n';
      final s = splitDocumentFrontMatter(src);
      expect(s.block, '');
      expect(s.body, src);
      expect(documentStyleName(src), isNull);
    });

    test('an empty --- --- block is not front matter', () {
      const src = '---\n\n---\n\nTekst.';
      expect(splitDocumentFrontMatter(src).block, '');
    });

    test('real front matter (opens with a key) is still recognised', () {
      const src = '---\ntheme: Europa\n---\n\n# Titel\n';
      final s = splitDocumentFrontMatter(src);
      expect(s.block, '---\ntheme: Europa\n---\n\n');
      expect(documentStyleName(src), 'Europa');
    });

    test('CRLF block splits and reassembles byte-exact', () {
      const src = '---\r\ntheme: Europa\r\n---\r\n\r\n# Titel\r\n';
      final s = splitDocumentFrontMatter(src);
      expect(s.block + s.body, src);
      expect(s.body, '# Titel\r\n');
    });
  });

  group('stripLeadingFrontMatterLeakage', () {
    test('plain body is unchanged', () {
      const body = '# Titel\n\nTekst.';
      expect(stripLeadingFrontMatterLeakage(body), body);
    });

    test('strips leaked front matter keys and fences', () {
      const body =
          'theme: Vigilis\ntlp: amber\n---\ntheme: Vigilis\ntlp: amber\n---\n# Titel\n\nTekst.';
      expect(stripLeadingFrontMatterLeakage(body), '# Titel\n\nTekst.');
    });

    test('does not strip without a --- fence', () {
      const body = 'theme: Vigilis\ntlp: amber\n# Titel\n';
      expect(stripLeadingFrontMatterLeakage(body), body);
    });

    test('stops at a blank line', () {
      const body = 'theme: Vigilis\n---\n\ntekst eronder\n';
      expect(stripLeadingFrontMatterLeakage(body), 'tekst eronder\n');
    });

    test('does not strip unknown keys', () {
      const body = 'foo: bar\n---\n# Titel\n';
      expect(stripLeadingFrontMatterLeakage(body), body);
    });

    test('strips ocideck_ keys too', () {
      const body = 'ocideck_format: 1\n---\n# Titel\n';
      expect(stripLeadingFrontMatterLeakage(body), '# Titel\n');
    });
  });

  group('documentStyleName', () {
    test('null without front matter', () {
      expect(documentStyleName('# Titel\n'), isNull);
    });
    test('null when front matter has no theme', () {
      expect(documentStyleName('---\ntitle: Memo\n---\n\nx'), isNull);
    });
    test('reads a bare value', () {
      expect(documentStyleName('---\ntheme: LibreKAT\n---\n\nx'), 'LibreKAT');
    });
    test('reads a quoted value among other keys', () {
      const src = '---\ntitle: Memo\ntheme: "Mijn stijl"\n---\n\nx';
      expect(documentStyleName(src), 'Mijn stijl');
    });
  });

  group('withDocumentStyleName', () {
    const plain = '# Titel\n\nTekst.';

    test('adds a block to a plain document', () {
      final out = withDocumentStyleName(plain, 'LibreKAT');
      expect(out, '---\ntheme: LibreKAT\n---\n\n# Titel\n\nTekst.');
      expect(documentStyleName(out), 'LibreKAT');
    });

    test('set then clear restores the exact plain bytes (byte-faithful)', () {
      final set = withDocumentStyleName(plain, 'Security');
      final cleared = withDocumentStyleName(set, null);
      expect(cleared, plain);
    });

    test('clearing on a plain document is a no-op', () {
      expect(withDocumentStyleName(plain, null), plain);
      expect(withDocumentStyleName(plain, ''), plain);
    });

    test('replaces an existing theme value, preserving other keys', () {
      const src = '---\ntitle: Memo\ntheme: Europa\n---\n\nx';
      final out = withDocumentStyleName(src, 'Security');
      expect(out, '---\ntitle: Memo\ntheme: Security\n---\n\nx');
    });

    test('inserts a theme into a block that had none, keeping other keys', () {
      const src = '---\ntitle: Memo\n---\n\nx';
      final out = withDocumentStyleName(src, 'Europa');
      expect(documentStyleName(out), 'Europa');
      expect(out.contains('title: Memo'), isTrue);
      expect(out.endsWith('\n\nx'), isTrue);
    });

    test('removing theme keeps a block that has other keys', () {
      const src = '---\ntitle: Memo\ntheme: Europa\n---\n\nx';
      final out = withDocumentStyleName(src, null);
      expect(out, '---\ntitle: Memo\n---\n\nx');
      expect(documentStyleName(out), isNull);
    });

    test('a name needing quotes round-trips through set→read', () {
      const tricky = 'Blauw: donker #1';
      final out = withDocumentStyleName(plain, tricky);
      expect(out.contains('theme: "Blauw: donker #1"'), isTrue);
      expect(documentStyleName(out), tricky);
    });

    test('CRLF document gets a CRLF block', () {
      const src = '# Titel\r\n\r\nTekst.\r\n';
      final out = withDocumentStyleName(src, 'Europa');
      expect(out.startsWith('---\r\ntheme: Europa\r\n---\r\n\r\n'), isTrue);
      expect(withDocumentStyleName(out, null), src);
    });

    test('documentBody drops the block', () {
      final set = withDocumentStyleName(plain, 'LibreKAT');
      expect(documentBody(set), plain);
    });
  });

  group('documentbrede TLP', () {
    const plain = '# Rapport\n\nInhoud.\n';

    test('elk niveau round-tript als één frontmatterwaarde', () {
      for (final level in TlpLevel.values.where((v) => v != TlpLevel.none)) {
        final classified = MarkdownDocument.parse(plain).withTlp(level);

        expect(classified.tlp, level, reason: level.name);
        expect(classified.body, plain, reason: level.name);
        expect(
          RegExp(r'^tlp:', multiLine: true).allMatches(classified.source),
          hasLength(1),
          reason: level.name,
        );
        expect(MarkdownDocument.parse(classified.source).tlp, level);
      }
    });

    test('zetten en wissen herstelt de exacte kale bron', () {
      final classified = MarkdownDocument.parse(
        plain,
      ).withTlp(TlpLevel.amberStrict);

      expect(classified.source, contains('tlp: amber+strict'));
      expect(classified.withTlp(TlpLevel.none).source, plain);
    });

    test('een andere sleutel en CRLF blijven bytegetrouw staan', () {
      const source =
          '---\r\n'
          'title: Handgeschreven\r\n'
          '---\r\n\r\n'
          '# Rapport\r\n';

      final classified = MarkdownDocument.parse(source).withTlp(TlpLevel.red);

      expect(classified.tlp, TlpLevel.red);
      expect(classified.source, contains('title: Handgeschreven\r\n'));
      expect(classified.source, contains('tlp: red\r\n'));
      expect(classified.withTlp(TlpLevel.none).source, source);
    });

    test('leest alleen top-level TLP en verwijdert inline commentaar', () {
      const nested = '---\nmeta:\n  tlp: red\ntlp: amber # beleid\n---\n\nBody';
      expect(MarkdownDocument.parse(nested).tlp, TlpLevel.amber);

      const onlyNested = '---\nmeta:\n  tlp: red\n---\n\nBody';
      expect(MarkdownDocument.parse(onlyNested).tlp, TlpLevel.none);
    });

    test('dubbele TLP kiest de strengste en schrijven maakt één regel', () {
      const source = '---\ntlp: clear\ntlp: red # tweede\n---\n\nBody';
      final document = MarkdownDocument.parse(source);
      expect(document.tlp, TlpLevel.red);

      final written = document.withTlp(TlpLevel.green);
      expect(written.tlp, TlpLevel.green);
      expect(
        RegExp(r'^tlp:', multiLine: true).allMatches(written.source),
        hasLength(1),
      );
      expect(written.source, contains('tlp: green\n'));
    });
  });

  group('vrije documentvelden', () {
    const body = '# Rapport\n\nInhoud.\n';

    test('toevoegen, wijzigen en wissen raakt bij LF alleen de velden', () {
      final added = withDocumentFields(body, const {
        'title': 'Kwartaalaudit',
        'subtitle': 'Bestuurlijke samenvatting',
        'author': 'Ada Lovelace',
        'project-id': 'P-42',
      });
      expect(
        added,
        '---\n'
        'title: Kwartaalaudit\n'
        'subtitle: Bestuurlijke samenvatting\n'
        'author: Ada Lovelace\n'
        'project-id: P-42\n'
        '---\n\n'
        '$body',
      );
      expect(documentFields(added), {
        'title': 'Kwartaalaudit',
        'subtitle': 'Bestuurlijke samenvatting',
        'author': 'Ada Lovelace',
        'project-id': 'P-42',
      });

      final edited = withDocumentFields(added, const {
        'title': 'Jaaraudit',
        'author': 'Ada Lovelace',
      });
      expect(edited, contains('title: Jaaraudit\n'));
      expect(edited, isNot(contains('subtitle:')));
      expect(edited, isNot(contains('project-id:')));
      expect(documentBody(edited), body);
      expect(withDocumentFields(edited, const {}), body);
    });

    test('CRLF, vreemde regels, commentaar en body blijven bytegetrouw', () {
      const source =
          '---\r\n'
          'title: Oud # handgeschreven commentaar\r\n'
          'nested:\r\n'
          '  child: blijft\r\n'
          'x.Vreemd: onaangeraakt\r\n'
          '---\r\n\r\n'
          '# Rapport\r\n';

      final edited = withDocumentFields(source, const {
        'title': 'Nieuw',
        'author': 'Grace Hopper',
      });

      expect(
        edited,
        '---\r\n'
        'title: Nieuw # handgeschreven commentaar\r\n'
        'nested:\r\n'
        '  child: blijft\r\n'
        'x.Vreemd: onaangeraakt\r\n'
        'author: Grace Hopper\r\n'
        '---\r\n\r\n'
        '# Rapport\r\n',
      );
      expect(
        withDocumentFields(edited, const {'title': 'Oud'}),
        '---\r\n'
        'title: Oud # handgeschreven commentaar\r\n'
        'nested:\r\n'
        '  child: blijft\r\n'
        'x.Vreemd: onaangeraakt\r\n'
        '---\r\n\r\n'
        '# Rapport\r\n',
      );
    });

    test('quote YAML-typen en ronde-tript leestekens, slash en Unicode', () {
      const values = {
        'boolean': 'true',
        'nothing': 'null',
        'colon': 'a: b',
        'quotes': r'zij zei "hoi" en \pad',
        'markdown': '**vet** # label',
        'unicode': 'R&D — Café ☕',
        'empty': '',
      };

      final source = withDocumentFields(body, values);

      expect(source, contains('boolean: "true"'));
      expect(source, contains('nothing: "null"'));
      expect(documentFields(source), values);
      expect(MarkdownDocument.parse(source).fields, values);
    });

    test('core-schema numerieken blijven volgens package:yaml strings', () {
      for (final value in [
        '.inf',
        '-.Inf',
        '.NaN',
        '+.NaN',
        '1e3',
        '-2E-4',
        '0x10',
        '+0x10',
        '0o10',
        '1_000',
      ]) {
        final source = withDocumentFields(body, {'value': value});
        final yaml = source.substring(4, source.indexOf('\n---\n'));
        expect((loadYaml(yaml) as YamlMap)['value'], value, reason: value);
        expect(documentFields(source)['value'], value, reason: value);
      }
    });

    test('weigert ongeldige, gereserveerde en meerregelige invoer', () {
      for (final key in [
        'Theme',
        '1title',
        'with space',
        'theme',
        'tlp',
        'papersize',
        'geometry',
        'reference-location',
        'ocideck_secret',
        'marp',
      ]) {
        expect(
          () => withDocumentFields(body, {key: 'waarde'}),
          throwsArgumentError,
          reason: key,
        );
      }
      expect(
        () => withDocumentFields(body, const {'title': 'regel 1\nregel 2'}),
        throwsArgumentError,
      );
      expect(
        () => withDocumentFields(body, {'title': 'x' * 4097}),
        throwsArgumentError,
      );
      expect(
        () => withDocumentFields(body, {
          for (var i = 0; i <= kMaxDocumentFields; i++) 'field-$i': 'x',
        }),
        throwsArgumentError,
      );
    });

    test('bestaande documenten boven de schrijfgrenzen blijven leesbaar', () {
      final source = [
        '---',
        for (var i = 0; i <= kMaxDocumentFields; i++) 'field-$i: x',
        'long: ${'x' * 4097}',
        '---',
        '',
        body,
      ].join('\n');
      final document = MarkdownDocument.parse(source);
      expect(document.fields, hasLength(kMaxDocumentFields + 2));
      expect(document.fields['long'], hasLength(4097));
      expect(document.toMarkdown(), source);
    });

    test('bodybewerkingen hergebruiken dezelfde frontmattermetadata', () {
      final document = MarkdownDocument.parse(
        '---\ntitle: Audit\n---\n\n$body',
      );
      final fields = document.fields;
      final edited = document.withSource('${document.frontMatter}# Gewijzigd');

      expect(identical(document.fields, fields), isTrue);
      expect(identical(edited.fields, fields), isTrue);
      expect(edited.fields, {'title': 'Audit'});
      expect(edited.body, '# Gewijzigd');
    });

    test('dubbele velden zijn zichtbaar en een bewerking maakt ze uniek', () {
      const duplicate =
          '---\n'
          'title: Eerste\n'
          'author: Ada\n'
          'title: Tweede\n'
          '---\n\n'
          '$body';

      expect(documentFields(duplicate)['title'], 'Eerste');
      expect(documentFieldDuplicateKeys(duplicate), {'title'});
      expect(
        (documentFields(duplicate) as DocumentFields).duplicateValues['title'],
        ['Eerste', 'Tweede'],
      );

      final repaired = withDocumentFields(duplicate, const {
        'title': 'Gekozen',
        'author': 'Ada',
      });
      expect(
        RegExp(r'^title:', multiLine: true).allMatches(repaired),
        hasLength(1),
      );
      expect(documentFields(repaired)['title'], 'Gekozen');
      expect(documentFieldDuplicateKeys(repaired), isEmpty);
    });

    test(
      'samengestelde YAML-waarden worden niet als platte velden gelezen',
      () {
        const source =
            '---\n'
            'title: "Audit: fase 1" # zichtbaar\n'
            "author: 'Ada ''A.'' Lovelace'\n"
            'list: [een, twee]\n'
            'map: {naam: Ada}\n'
            'literal: |\n'
            '  meerdere regels\n'
            'alias: *persoon\n'
            '---\n\n'
            '$body';

        expect(documentFields(source), {
          'title': 'Audit: fase 1',
          'author': "Ada 'A.' Lovelace",
        });
      },
    );

    // Regression voor #1638: de vrije sleutel `marp` laat sniffFrontmatter
    // het bestand na heropenen als presentatie lezen, wat de documentbron
    // stil in dia's deconstrueert. `marp` is dus een gereserveerde
    // documentsleutel — hij mag niet via de velden worden geschreven.
    test('marp is een gereserveerde sleutel en wordt niet weggeschreven', () {
      expect(isReservedDocumentFieldKey('marp'), isTrue);
      expect(
        () => withDocumentFields(body, const {'marp': 'true'}),
        throwsArgumentError,
      );
      // Een handgeschreven `marp: true` wordt niet als vrij veld blootgesteld,
      // zodat de veldendialoog hem niet kan round-trippen als documentveld.
      const source = '---\nmarp: true\ntitle: Audit\n---\n\n$body';
      expect(documentFields(source), isNot(contains('marp')));
      expect(documentFields(source), {'title': 'Audit'});
    });
  });
}
