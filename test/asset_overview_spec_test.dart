import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/asset_overview_spec.dart';

AssetOverviewSpec _parse(List<List<String>> rows) =>
    AssetOverviewSpec.fromSlide('Ons aanvalsoppervlak', rows);

const _estate = AssetOverviewSpec(
  title: 'Ons aanvalsoppervlak',
  groups: [
    AssetGroup(
      name: 'Webapplicaties',
      total: 182,
      atRisk: 12,
      newlyFound: 7,
      unowned: 3,
    ),
    AssetGroup(name: 'Mailservers', total: 24, atRisk: 1),
    AssetGroup(name: 'VPN-endpoints', total: 3, atRisk: 2),
  ],
);

void main() {
  group('AssetOverviewSpec totals', () {
    test('every total is derived from the rows', () {
      expect(_estate.totalAssets, 209);
      expect(_estate.totalAtRisk, 15);
      expect(_estate.totalNew, 7);
      expect(_estate.totalUnowned, 3);
    });

    test('an empty overview totals nothing rather than throwing', () {
      const empty = AssetOverviewSpec();
      expect(empty.totalAssets, 0);
      expect(empty.largestGroup, 0);
      expect(empty.isEmpty, isTrue);
    });

    test('the largest group sets one shared scale for the bars', () {
      // Without a shared scale a category of three would draw the same width as
      // a category of three hundred.
      expect(_estate.largestGroup, 182);
    });
  });

  group('AssetGroup proportions', () {
    test('the at-risk fraction is the share of the group', () {
      const g = AssetGroup(name: 'X', total: 200, atRisk: 50);
      expect(g.atRiskFraction, 0.25);
    });

    test(
      'a group of nothing has no fraction rather than a division by zero',
      () {
        const g = AssetGroup(name: 'X', total: 0, atRisk: 0);
        expect(g.atRiskFraction, 0);
      },
    );

    test('an impossible count is shown, but the bar stays within its row', () {
      const wrong = AssetGroup(name: 'X', total: 182, atRisk: 200);
      // The bar cannot overrun...
      expect(wrong.atRiskFraction, 1.0);
      // ...but the figure itself is not quietly corrected, because that would
      // hide the bug in whatever produced it.
      expect(wrong.atRisk, 200);
      expect(wrong.isConsistent, isFalse);
    });

    test('ordinary counts read as consistent', () {
      expect(_estate.groups.first.isConsistent, isTrue);
    });
  });

  group('AssetOverviewSpec round-trip', () {
    test('toTableRows/fromSlide is a fixed point', () {
      final again = _parse(_estate.toTableRows());
      expect(again.groups.length, 3);
      final web = again.groups.first;
      expect(web.name, 'Webapplicaties');
      expect(web.total, 182);
      expect(web.atRisk, 12);
      expect(web.newlyFound, 7);
      expect(web.unowned, 3);
      expect(again.toTableRows(), _estate.toTableRows());
    });

    test('a blank row never reaches the table on write either', () {
      const spec = AssetOverviewSpec(
        groups: [
          AssetGroup(name: 'X', total: 1),
          AssetGroup(),
        ],
      );
      expect(spec.toTableRows().length, 2);
      expect(_parse(spec.toTableRows()).groups.length, 1);
    });
  });

  group('AssetOverviewSpec tolerant parse', () {
    test('the header row is skipped', () {
      final spec = _parse([
        AssetOverviewSpec.header,
        ['Webapplicaties', '182', '12', '7', '3'],
      ]);
      expect(spec.groups.single.name, 'Webapplicaties');
    });

    test('an unreadable count reads as nought without costing the row', () {
      final spec = _parse([
        AssetOverviewSpec.header,
        ['Webapplicaties', 'veel', '12', '', ''],
      ]);
      final group = spec.groups.single;
      expect(group.name, 'Webapplicaties');
      expect(group.total, 0);
      expect(group.atRisk, 12);
    });

    test('a negative count is refused rather than subtracted from a total', () {
      // There is no such thing as minus three servers.
      expect(parseAssetCount('-3'), isNull);
      final spec = _parse([
        AssetOverviewSpec.header,
        ['Webapplicaties', '10', '-3', '', ''],
      ]);
      expect(spec.groups.single.atRisk, 0);
      expect(spec.totalAtRisk, 0);
    });

    test('a named group with no figures yet survives', () {
      final spec = _parse([
        AssetOverviewSpec.header,
        ['Nog te tellen', '', '', '', ''],
        ['', '', '', '', ''],
      ]);
      expect(spec.groups.single.name, 'Nog te tellen');
      expect(spec.groups.single.total, 0);
    });

    test('short rows read as absent cells, not as an error', () {
      final spec = _parse([
        ['Webapplicaties', '182'],
      ]);
      expect(spec.groups.single.total, 182);
      expect(spec.groups.single.unowned, 0);
    });

    test('more groups than fit are capped on read', () {
      final spec = _parse([
        AssetOverviewSpec.header,
        for (var i = 0; i < assetOverviewMaxGroups + 3; i++) ['G$i', '1'],
      ]);
      expect(spec.groups.length, assetOverviewMaxGroups);
    });
  });

  group('parseAssetCount', () {
    test('reads a plain count', () {
      expect(parseAssetCount(' 182 '), 182);
      expect(parseAssetCount('0'), 0);
    });

    test('refuses what it cannot read', () {
      expect(parseAssetCount(''), isNull);
      expect(parseAssetCount('veel'), isNull);
      expect(parseAssetCount('1.5'), isNull);
    });
  });
}
