import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/discoveries_spec.dart';

/// A spec with one exposure per entry, for the derived figures.
DiscoveriesSpec _spec(List<int?> days) => DiscoveriesSpec(
  discoveries: [
    for (var i = 0; i < days.length; i++)
      Discovery(name: 'find $i', daysUnnoticed: days[i]),
  ],
);

void main() {
  group('table round-trip', () {
    test('a discovery survives a write and a read unchanged', () {
      const spec = DiscoveriesSpec(
        title: 'Wat we niet wisten te hebben',
        discoveries: [
          Discovery(
            name: 'betaalportaal-acc.example.nl',
            kind: 'Webapplicatie',
            daysUnnoticed: 412,
            owner: 'Team Betalen',
          ),
        ],
      );

      final back = DiscoveriesSpec.fromSlide(spec.title, spec.toTableRows());

      expect(back.title, spec.title);
      expect(back.discoveries, hasLength(1));
      final discovery = back.discoveries.single;
      expect(discovery.name, 'betaalportaal-acc.example.nl');
      expect(discovery.kind, 'Webapplicatie');
      expect(discovery.daysUnnoticed, 412);
      expect(discovery.owner, 'Team Betalen');
    });

    test('the fixed header is written and read back as a header', () {
      const spec = DiscoveriesSpec(
        discoveries: [Discovery(name: 'iets', daysUnnoticed: 3)],
      );
      final rows = spec.toTableRows();

      expect(rows.first, DiscoveriesSpec.header);
      // Read back it is a header and not a discovery called "Discovery".
      expect(DiscoveriesSpec.fromSlide('', rows).discoveries, hasLength(1));
    });

    test('blank rows never reach disk and never come back', () {
      const spec = DiscoveriesSpec(
        discoveries: [
          Discovery(name: 'echt'),
          Discovery(),
        ],
      );

      expect(spec.toTableRows(), hasLength(2)); // header + the real one
      expect(
        DiscoveriesSpec.fromSlide('', [
          DiscoveriesSpec.header,
          ['echt', '', '', ''],
          ['', '', '', ''],
        ]).discoveries,
        hasLength(1),
      );
    });

    test('a short row is read rather than dropped', () {
      // A generator that writes only the name should still produce a slide.
      final spec = DiscoveriesSpec.fromSlide('', [
        DiscoveriesSpec.header,
        ['alleen-een-naam.example.nl'],
      ]);

      expect(spec.discoveries.single.name, 'alleen-een-naam.example.nl');
      expect(spec.discoveries.single.kind, '');
      expect(spec.discoveries.single.daysUnnoticed, isNull);
    });

    test('the ceiling holds on both read and write', () {
      final tooMany = DiscoveriesSpec(
        discoveries: [
          for (var i = 0; i < discoveriesMaxEntries + 4; i++)
            Discovery(name: 'find $i'),
        ],
      );

      // Written: header + exactly the ceiling.
      expect(tooMany.toTableRows(), hasLength(discoveriesMaxEntries + 1));
      // Read: a hand-edited file with too many rows is trimmed as well.
      expect(
        DiscoveriesSpec.fromSlide('', [
          DiscoveriesSpec.header,
          for (var i = 0; i < discoveriesMaxEntries + 4; i++)
            ['find $i', '', '', ''],
        ]).discoveries,
        hasLength(discoveriesMaxEntries),
      );
    });
  });

  group('an unknown exposure stays unknown', () {
    test('an empty cell reads as null, not as nought', () {
      expect(parseDaysUnnoticed(''), isNull);
      expect(parseDaysUnnoticed('   '), isNull);
    });

    test('unreadable and negative figures read as unknown', () {
      // Reading "-3" as zero would claim the object was found the day it
      // appeared, which is a far stronger statement than "we do not know".
      expect(parseDaysUnnoticed('-3'), isNull);
      expect(parseDaysUnnoticed('gisteren'), isNull);
      expect(parseDaysUnnoticed('0'), 0);
      expect(parseDaysUnnoticed(' 412 '), 412);
    });

    test('null survives the round-trip as an empty cell', () {
      const spec = DiscoveriesSpec(discoveries: [Discovery(name: 'x')]);

      expect(spec.toTableRows()[1][2], '');
      expect(
        DiscoveriesSpec.fromSlide(
          '',
          spec.toTableRows(),
        ).discoveries.single.daysUnnoticed,
        isNull,
      );
    });
  });

  group('derived figures', () {
    test('the longest exposure is the largest known figure', () {
      expect(_spec([12, 412, 90]).longestUnnoticed, 412);
    });

    test('rows without a figure do not drag the longest down', () {
      expect(_spec([null, 412, null]).longestUnnoticed, 412);
    });

    test('with nothing known at all there is no headline to make', () {
      // The slide must not imply a history it does not have.
      expect(_spec([null, null]).longestUnnoticed, isNull);
      expect(const DiscoveriesSpec().longestUnnoticed, isNull);
    });

    test('bars are scaled to the longest exposure, not to their own row', () {
      final spec = _spec([412, 206, 412]);

      expect(spec.barFraction(spec.discoveries[0]), 1.0);
      expect(spec.barFraction(spec.discoveries[1]), closeTo(0.5, 0.001));
    });

    test('an unknown exposure draws no bar', () {
      final spec = _spec([412, null]);

      expect(spec.barFraction(spec.discoveries[1]), 0);
    });

    test('bars do not divide by zero when everything was found at once', () {
      final spec = _spec([0, 0]);

      expect(spec.barFraction(spec.discoveries[0]), 0);
    });

    test('the unowned tally counts blank and whitespace owners alike', () {
      const spec = DiscoveriesSpec(
        discoveries: [
          Discovery(name: 'a', owner: 'Team Betalen'),
          Discovery(name: 'b'),
          Discovery(name: 'c', owner: '   '),
        ],
      );

      expect(spec.count, 3);
      expect(spec.unownedCount, 2);
    });
  });

  group('restating an exposure for a reader', () {
    test('short exposures stay in days, where days are the precise word', () {
      expect(scaleDaysUnnoticed(1), (value: 1, inMonths: false));
      expect(scaleDaysUnnoticed(59), (value: 59, inMonths: false));
    });

    test('long exposures are restated in months', () {
      // 420 days means nothing at a glance; fourteen months lands.
      expect(scaleDaysUnnoticed(420), (value: 14, inMonths: true));
      expect(scaleDaysUnnoticed(60), (value: 2, inMonths: true));
    });
  });

  test('copyWith can clear an exposure as well as set one', () {
    const discovery = Discovery(name: 'x', daysUnnoticed: 412);

    expect(discovery.copyWith(daysUnnoticed: 3).daysUnnoticed, 3);
    // Without the explicit flag a null argument cannot be told from "leave it".
    expect(discovery.copyWith().daysUnnoticed, 412);
    expect(discovery.copyWith(clearDaysUnnoticed: true).daysUnnoticed, isNull);
  });
}
