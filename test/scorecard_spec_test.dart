import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/scorecard_spec.dart';

ScorecardSpec _parse(List<List<String>> rows) =>
    ScorecardSpec.fromSlide('Sinds de vorige rapportage', rows);

void main() {
  group('ScorecardEntry', () {
    test('delta and direction come from the two figures', () {
      const fell = ScorecardEntry(label: 'Open', value: 96, previous: 120);
      expect(fell.delta, -24);
      expect(fell.direction, ScorecardDirection.down);

      const rose = ScorecardEntry(label: 'Assets', value: 412, previous: 375);
      expect(rose.delta, 37);
      expect(rose.direction, ScorecardDirection.up);
    });

    test('without a previous figure there is no delta at all', () {
      const first = ScorecardEntry(label: 'Open', value: 96);
      expect(first.delta, isNull);
      expect(first.direction, isNull);
      // Not "unchanged": the figure was never measured before, and a zero
      // delta would claim it held steady.
      expect(first.sentiment, ScorecardSentiment.neutral);
    });

    test('an unchanged figure is flat and carries no judgement', () {
      const same = ScorecardEntry(
        label: 'Kritiek',
        value: 8,
        previous: 8,
        polarity: ScorecardPolarity.lowerBetter,
      );
      expect(same.direction, ScorecardDirection.flat);
      expect(same.sentiment, ScorecardSentiment.neutral);
    });

    test('polarity decides the colour, the numbers decide the arrow', () {
      const fewerIsBetter = ScorecardEntry(
        label: 'Open',
        value: 96,
        previous: 120,
        polarity: ScorecardPolarity.lowerBetter,
      );
      expect(fewerIsBetter.direction, ScorecardDirection.down);
      expect(fewerIsBetter.sentiment, ScorecardSentiment.good);

      const moreIsBetter = ScorecardEntry(
        label: 'Gedekt',
        value: 96,
        previous: 120,
        polarity: ScorecardPolarity.higherBetter,
      );
      expect(moreIsBetter.direction, ScorecardDirection.down);
      expect(moreIsBetter.sentiment, ScorecardSentiment.bad);
    });

    test('a neutral figure shows the change but withholds the verdict', () {
      const counted = ScorecardEntry(
        label: 'Assets in beeld',
        value: 412,
        previous: 375,
      );
      expect(counted.direction, ScorecardDirection.up);
      expect(counted.sentiment, ScorecardSentiment.neutral);
    });

    test('a float artefact does not read as a change', () {
      final drift = ScorecardEntry(
        label: 'Gemiddelde',
        value: 0.1 + 0.2,
        previous: 0.3,
        polarity: ScorecardPolarity.lowerBetter,
      );
      expect(drift.direction, ScorecardDirection.flat);
      expect(drift.sentiment, ScorecardSentiment.neutral);
    });
  });

  group('ScorecardSpec round-trip', () {
    test('toTableRows/fromSlide is a fixed point', () {
      const spec = ScorecardSpec(
        title: 'Sinds de vorige rapportage',
        entries: [
          ScorecardEntry(
            label: 'Assets in beeld',
            value: 412,
            previous: 375,
          ),
          ScorecardEntry(
            label: 'Gemiddeld openstaand',
            value: 62.5,
            previous: 73,
            unit: 'dagen',
            polarity: ScorecardPolarity.lowerBetter,
          ),
        ],
      );
      final again = _parse(spec.toTableRows());
      expect(again.entries.length, 2);
      expect(again.entries[1].label, 'Gemiddeld openstaand');
      expect(again.entries[1].value, 62.5);
      expect(again.entries[1].previous, 73);
      expect(again.entries[1].unit, 'dagen');
      expect(again.entries[1].polarity, ScorecardPolarity.lowerBetter);
      expect(again.toTableRows(), spec.toTableRows());
    });

    test('an absent previous stays absent rather than becoming a zero', () {
      const spec = ScorecardSpec(
        entries: [ScorecardEntry(label: 'Open', value: 96)],
      );
      expect(spec.toTableRows()[1][2], '');
      expect(_parse(spec.toTableRows()).entries.single.previous, isNull);
    });

    test('whole numbers keep no decimal tail on disk', () {
      const spec = ScorecardSpec(
        entries: [ScorecardEntry(label: 'Open', value: 96, previous: 120)],
      );
      expect(spec.toTableRows()[1][1], '96');
      expect(spec.toTableRows()[1][2], '120');
    });
  });

  group('ScorecardSpec tolerant parse', () {
    test('the header row is skipped', () {
      final spec = _parse([
        ScorecardSpec.header,
        ['Open', '96', '120', '', 'lower-better'],
      ]);
      expect(spec.entries.single.label, 'Open');
    });

    test('rows without a label or a readable figure are dropped', () {
      final spec = _parse([
        ScorecardSpec.header,
        ['', '96', '', '', ''],
        ['Geen getal', 'nvt', '', '', ''],
        ['Open', '96', '', '', ''],
      ]);
      expect(spec.entries.map((e) => e.label), ['Open']);
    });

    test('an unreadable previous only costs the delta, not the row', () {
      final spec = _parse([
        ScorecardSpec.header,
        ['Open', '96', 'onbekend', '', 'lower-better'],
      ]);
      expect(spec.entries.single.value, 96);
      expect(spec.entries.single.previous, isNull);
      expect(spec.entries.single.polarity, ScorecardPolarity.lowerBetter);
    });

    test('an unrecognised polarity falls back to neutral', () {
      final spec = _parse([
        ScorecardSpec.header,
        ['Open', '96', '120', '', 'omhoog-is-goed'],
      ]);
      expect(spec.entries.single.polarity, ScorecardPolarity.neutral);
      expect(spec.entries.single.direction, ScorecardDirection.down);
      expect(spec.entries.single.sentiment, ScorecardSentiment.neutral);
    });

    test('short rows read as absent cells, not as an error', () {
      final spec = _parse([
        ['Open', '96'],
      ]);
      expect(spec.entries.single.value, 96);
      expect(spec.entries.single.previous, isNull);
      expect(spec.entries.single.unit, '');
      expect(spec.entries.single.polarity, ScorecardPolarity.neutral);
    });

    test('more figures than fit are capped on read', () {
      final spec = _parse([
        ScorecardSpec.header,
        for (var i = 0; i < scorecardMaxEntries + 3; i++) ['F$i', '$i'],
      ]);
      expect(spec.entries.length, scorecardMaxEntries);
      expect(spec.entries.last.label, 'F${scorecardMaxEntries - 1}');
    });
  });

  group('parseScorecardNumber', () {
    test('reads a plain figure', () {
      expect(parseScorecardNumber(' 412 '), 412);
      expect(parseScorecardNumber('62.5'), 62.5);
      expect(parseScorecardNumber('-3'), -3);
    });

    test('accepts a comma decimal when it is unambiguous', () {
      expect(parseScorecardNumber('62,5'), 62.5);
    });

    test('refuses what it cannot read without guessing', () {
      expect(parseScorecardNumber(''), isNull);
      expect(parseScorecardNumber('nvt'), isNull);
      // Thousands separators are genuinely ambiguous — 1.234 and 1,234 mean
      // different things in different locales, so neither is guessed at.
      expect(parseScorecardNumber('1,234,567'), isNull);
    });
  });

  group('formatScorecardNumber', () {
    test('drops the tail on whole figures and keeps it otherwise', () {
      expect(formatScorecardNumber(96), '96');
      expect(formatScorecardNumber(62.5), '62.5');
      expect(formatScorecardNumber(-3), '-3');
    });
  });

  test('every polarity has a Dutch source label', () {
    for (final polarity in ScorecardPolarity.values) {
      expect(scorecardPolarityDutchLabel(polarity), isNotEmpty);
    }
  });
}
