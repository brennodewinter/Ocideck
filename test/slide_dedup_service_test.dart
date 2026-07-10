import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/slide_dedup_service.dart';

/// A slide with a caller-chosen id, so tests can prove that de-duplication is
/// content-based (equal content, different ids) rather than id-based.
Slide _slide(
  String id, {
  SlideType type = SlideType.bullets,
  String title = '',
  List<String> bullets = const [],
  String customMarkdown = '',
  String notes = '',
}) => Slide(
  id: id,
  type: type,
  title: title,
  bullets: bullets,
  customMarkdown: customMarkdown,
  notes: notes,
);

void main() {
  final service = SlideDedupService();

  group('dedupe', () {
    test('bundelt inhoudelijk identieke slides met verschillende ids', () {
      final a = _slide('1', title: 'Scope', bullets: const ['x', 'y']);
      final b = _slide('2', title: 'Scope', bullets: const ['x', 'y']);
      final c = _slide('3', title: 'Anders', bullets: const ['z']);

      final result = service.dedupe([a, b, c], (s) => s);

      expect(result.groups, hasLength(2));
      expect(result.groups.first.copies, 2);
      expect(result.groups.first.primary.id, '1');
      expect(result.groups.first.occurrences.map((s) => s.id), ['1', '2']);
      expect(result.groups.last.copies, 1);
      expect(result.truncated, isFalse);
    });

    test('houdt de eerste vindplaats als primaire, in scanvolgorde', () {
      final a = _slide('a', title: 'T', bullets: const ['one']);
      final dupe = _slide('b', title: 'T', bullets: const ['one']);
      final result = service.dedupe([a, dupe], (s) => s);
      expect(result.groups, hasLength(1));
      expect(result.groups.single.primary.id, 'a');
    });

    test('slides die alleen in notities verschillen zijn geen duplicaat', () {
      // Notities reizen met de slide mee, dus samenvoegen zou ze stilzwijgend
      // laten vallen; ze blijven gescheiden en worden als gelijkend gekoppeld.
      final a = _slide('1', title: 'T', bullets: const ['a'], notes: 'links');
      final b = _slide('2', title: 'T', bullets: const ['a'], notes: 'rechts');
      final result = service.dedupe([a, b], (s) => s);
      expect(result.groups, hasLength(2));
      expect(result.similar[0], [1]);
      expect(
        service.diff(a, b).map((d) => d.field),
        contains(SlideField.notes),
      );
    });

    test(
      'maxGroups kapt het aantal unieke slides af, maar telt kopieën door',
      () {
        final items = [
          _slide('1', title: 'A'),
          _slide('2', title: 'A'), // kopie van 1
          _slide('3', title: 'B'),
          _slide('4', title: 'C'),
        ];
        final result = service.dedupe(items, (s) => s, maxGroups: 1);
        expect(result.groups, hasLength(1));
        expect(result.groups.single.copies, 2);
        expect(result.truncated, isTrue);
      },
    );
  });

  group('gelijkenis', () {
    test('koppelt slides met dezelfde titel maar afwijkende inhoud', () {
      final a = _slide('1', title: 'Bevindingen', bullets: const ['SQLi']);
      final b = _slide('2', title: 'Bevindingen', bullets: const ['XSS']);

      final result = service.dedupe([a, b], (s) => s);

      expect(result.groups, hasLength(2));
      expect(result.similar[0], [1]);
      expect(result.similar[1], [0]);
    });

    test(
      'koppelt titelloze slides van hetzelfde type bij hoge tekstgelijkenis',
      () {
        final a = _slide(
          '1',
          type: SlideType.freeMarkdown,
          customMarkdown: 'The quick brown fox jumps over the lazy dog today.',
        );
        final b = _slide(
          '2',
          type: SlideType.freeMarkdown,
          customMarkdown: 'The quick brown fox jumps over the lazy cat today.',
        );

        final result = service.dedupe([a, b], (s) => s);
        expect(result.groups, hasLength(2));
        expect(result.similar[0], [1]);
      },
    );

    test('koppelt niet bij lage tekstgelijkenis', () {
      final a = _slide(
        '1',
        type: SlideType.freeMarkdown,
        customMarkdown: 'Appels en peren uit de boomgaard.',
      );
      final b = _slide(
        '2',
        type: SlideType.freeMarkdown,
        customMarkdown: 'Volledig andere inhoud over netwerksegmentatie.',
      );

      final result = service.dedupe([a, b], (s) => s);
      expect(result.similar[0], isEmpty);
      expect(result.similar[1], isEmpty);
    });

    test(
      'identieke slides zijn geen "gelijkende" — ze zijn al samengevoegd',
      () {
        final a = _slide('1', title: 'T', bullets: const ['x']);
        final b = _slide('2', title: 'T', bullets: const ['x']);
        final result = service.dedupe([a, b], (s) => s);
        expect(result.groups, hasLength(1));
        expect(result.similar.single, isEmpty);
      },
    );
  });

  group('diff', () {
    test('somt alleen de afwijkende velden op', () {
      final a = _slide('1', title: 'Scope', bullets: const ['a', 'b']);
      final b = _slide('2', title: 'Scope', bullets: const ['a', 'c']);

      final diffs = service.diff(a, b);

      expect(diffs.map((d) => d.field), [SlideField.bullets]);
      expect(diffs.single.before, 'a\nb');
      expect(diffs.single.after, 'a\nc');
    });

    test('vangt zowel titel- als inhoudsverschillen', () {
      final a = _slide('1', title: 'Oud', bullets: const ['x']);
      final b = _slide('2', title: 'Nieuw', bullets: const ['y']);
      final fields = service.diff(a, b).map((d) => d.field).toSet();
      expect(fields, containsAll([SlideField.title, SlideField.bullets]));
    });

    test('geen verschillen voor identieke slides', () {
      final a = _slide('1', title: 'T', bullets: const ['x']);
      final b = _slide('2', title: 'T', bullets: const ['x']);
      expect(service.diff(a, b), isEmpty);
    });
  });

  test(
    'signatureOf is stabiel voor gelijke inhoud en verschilt bij wijziging',
    () {
      final a = _slide('1', title: 'T', bullets: const ['x']);
      final b = _slide('2', title: 'T', bullets: const ['x']);
      final c = _slide('3', title: 'T', bullets: const ['y']);
      expect(service.signatureOf(a), service.signatureOf(b));
      expect(service.signatureOf(a), isNot(service.signatureOf(c)));
    },
  );
}
