import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/question.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/package_asset_resolver.dart';
import 'package:ocideck/services/slide_image_refs.dart';
import 'package:ocideck/services/web_asset_store.dart';

/// De centrale helper die de vraag "welke afbeeldingen gebruikt deze dia"
/// beantwoordt. Hij is de enige plek waar het antwoord staat, dus een fout hier
/// plant zich voort naar de sweep, de opruimer en de export tegelijk.
void main() {
  Slide slideWith({
    String imagePath = '',
    String imagePath2 = '',
    String customMarkdown = '',
  }) => Slide.create(SlideType.freeMarkdown).copyWith(
    imagePath: imagePath,
    imagePath2: imagePath2,
    customMarkdown: customMarkdown,
  );

  group('slideImageRefs', () {
    test('geeft de velden en daarna de tekst, in leesvolgorde', () {
      final refs = slideImageRefs(
        slideWith(
          imagePath: 'images/een.png',
          imagePath2: 'images/twee.png',
          customMarkdown: 'Tekst ![alt drie](images/drie.png) meer tekst.',
        ),
      );

      expect(refs.map((r) => r.path), [
        'images/een.png',
        'images/twee.png',
        'images/drie.png',
      ]);
      expect(refs.map((r) => r.slot), [
        SlideImageSlot.image,
        SlideImageSlot.image2,
        SlideImageSlot.inline,
      ]);
      expect(refs.last.alt, 'alt drie');
    });

    test('een leeg veld is geen verwijzing', () {
      expect(slideImageRefs(slideWith(imagePath: '   ')), isEmpty);
    });

    test('meerdere afbeeldingen in dezelfde tekst komen alle mee', () {
      final paths = slideImagePaths(
        slideWith(customMarkdown: '![a](een.png)\n\n![b](twee.png)\n'),
      );
      expect(paths, ['een.png', 'twee.png']);
    });

    test('inlineImagePaths leest de maatvoering als gewone alt-tekst', () {
      expect(inlineImagePaths('![w:600 h:400](foto.png)'), ['foto.png']);
    });
  });

  group('rewriteInlineImagePaths', () {
    test('vervangt alleen het pad en laat de alt-tekst staan', () {
      final out = rewriteInlineImagePaths(
        'Zie ![w:600 mijn foto](oud.png) hier.',
        (path) => path == 'oud.png' ? 'images/nieuw.png' : null,
      );
      expect(out, 'Zie ![w:600 mijn foto](images/nieuw.png) hier.');
    });

    test('null laat de verwijzing onaangeroerd', () {
      const md = '![a](een.png) en ![b](twee.png)';
      expect(
        rewriteInlineImagePaths(md, (path) => path == 'een.png' ? 'X' : null),
        '![a](X) en ![b](twee.png)',
      );
    });
  });

  group('rewriteSlideImagePaths', () {
    test('herschrijft de velden én de tekst', () {
      final out = rewriteSlideImagePaths(
        slideWith(
          imagePath: 'a.png',
          imagePath2: 'b.png',
          customMarkdown: 'x ![alt](c.png) y',
        ),
        (path) => 'images/$path',
      );

      expect(out.imagePath, 'images/a.png');
      expect(out.imagePath2, 'images/b.png');
      expect(out.customMarkdown, 'x ![alt](images/c.png) y');
    });

    test('geeft dezelfde dia terug als er niets te herschrijven valt', () {
      final slide = slideWith(
        imagePath: 'a.png',
        customMarkdown: '![x](c.png)',
      );
      expect(
        identical(rewriteSlideImagePaths(slide, (_) => null), slide),
        true,
      );
    });
  });

  group('imagePair-vraag (#853)', () {
    tearDown(WebAssetStore.clear);

    QuestionSpec imagePair(String a, String b) => QuestionSpec(
      kind: QuestionKind.imagePair,
      prompt: 'Welke?',
      answers: [
        QuestionAnswer(text: 'A', correct: true, image: a),
        QuestionAnswer(text: 'B', correct: false, image: b),
      ],
    );
    Slide questionSlide(QuestionSpec spec) => Slide.create(
      SlideType.question,
    ).copyWith(customMarkdown: spec.toBlock());

    test(
      'slideImageRefs geeft de antwoord-afbeeldingen (questionImage-slot)',
      () {
        final refs = slideImageRefs(
          questionSlide(imagePair('images/kat.png', 'images/hond.png')),
        );
        expect(refs.map((r) => r.path), ['images/kat.png', 'images/hond.png']);
        expect(refs.map((r) => r.slot), [
          SlideImageSlot.questionImage,
          SlideImageSlot.questionImage,
        ]);
        expect(refs.first.alt, 'A');
      },
    );

    test('rewriteSlideImagePaths verlegt de antwoord-paden in het blok', () {
      final slide = questionSlide(
        imagePair('images/kat.png', 'images/hond.png'),
      );
      final out = rewriteSlideImagePaths(
        slide,
        (p) => p == 'images/kat.png' ? 'mem:xyz' : null,
      );
      final spec = QuestionSpec.parse(out.customMarkdown);
      expect(spec.answers.map((a) => a.image), ['mem:xyz', 'images/hond.png']);
    });

    test('rewriteSlideImagePaths laat het blok met rust zonder treffer', () {
      final slide = questionSlide(
        imagePair('images/kat.png', 'images/hond.png'),
      );
      expect(
        identical(rewriteSlideImagePaths(slide, (_) => null), slide),
        true,
      );
    });

    test('negen antwoord-afbeeldingen blijven zichtbaar voor opslag', () {
      final source = const JsonEncoder.withIndent('  ').convert({
        'kind': 'imagePair',
        'prompt': 'Welke?',
        'answers': [
          for (var i = 0; i < 9; i++)
            {
              'text': 'Beeld $i',
              'correct': i.isEven,
              'image': 'images/$i.png',
              'extensionField': 'blijft-$i',
            },
        ],
        'extensionRoot': {'blijft': true},
      });
      final slide = Slide.create(
        SlideType.question,
      ).copyWith(customMarkdown: source);

      expect(slideImagePaths(slide), [
        for (var i = 0; i < 9; i++) 'images/$i.png',
      ]);

      final rewritten = rewriteSlideImagePaths(
        slide,
        (path) => path == 'images/8.png' ? 'mem:acht' : null,
      );
      final json = jsonDecode(rewritten.customMarkdown) as Map<String, dynamic>;
      final answers = json['answers'] as List<dynamic>;
      expect((answers[8] as Map<String, dynamic>)['image'], 'mem:acht');
      expect(
        (answers[8] as Map<String, dynamic>)['extensionField'],
        'blijft-8',
      );
      expect(json['extensionRoot'], {'blijft': true});
    });

    test('attachPackageAssetsToMem zet de antwoord-beelden in mem:', () {
      final kat = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]);
      final hond = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 5, 6, 7, 8]);
      final out = attachPackageAssetsToMem(
        Deck(
          title: 'demo',
          slides: [
            questionSlide(imagePair('images/kat.png', 'images/hond.png')),
          ],
        ),
        <({String name, Uint8List bytes})>[
          (name: 'images/kat.png', bytes: kat),
          (name: 'images/hond.png', bytes: hond),
        ],
        'demo.md',
      );
      final paths = QuestionSpec.parse(
        out.slides[0].customMarkdown,
      ).answers.map((a) => a.image).toList();
      expect(paths.every(WebAssetStore.isMemPath), isTrue);
      expect(WebAssetStore.bytesFor(paths[0]), kat);
      expect(WebAssetStore.bytesFor(paths[1]), hond);
    });
  });
}
