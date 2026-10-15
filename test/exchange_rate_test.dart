import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/attendee_input.dart';
import 'package:ocideck/models/exchange_rate.dart';
import 'package:ocideck/models/presentation_cost.dart';
import 'package:ocideck/services/exchange_rate_service.dart';
import 'package:ocideck/services/presentation_cost_session.dart';
import 'package:ocideck/widgets/dialogs/currency_conversion_dialog.dart';

const _eur = CostCurrency('EUR', '€', 2);
const _usd = CostCurrency('USD', '\$', 2);
const _gbp = CostCurrency('GBP', '£', 2);
const _jpy = CostCurrency('JPY', '¥', 0);

ExchangeRate _rate(String code, int micros, {String date = '2026-10-15'}) =>
    ExchangeRate(
      code: code,
      eurMicros: micros,
      source: 'Frankfurter (ECB)',
      date: date,
      manual: false,
    );

String _isoDaysAgo(int days) {
  final d = DateTime.now().subtract(Duration(days: days));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

void main() {
  group('parseRateMicros', () {
    test('leest komma en punt, met en zonder decimalen', () {
      expect(parseRateMicros('0,92'), 920000);
      expect(parseRateMicros('0.92'), 920000);
      expect(parseRateMicros('1'), 1000000);
      expect(parseRateMicros(' 1,5 '), 1500000);
      expect(parseRateMicros('0,000001'), 1);
    });

    test('weigert wat geen eerlijke koers is', () {
      for (final bad in [
        '',
        '0',
        '0,0',
        '-1',
        'abc',
        '1,2,3',
        '0,0000001', // zeven decimalen: niet terug te spiegelen
        '1e-3',
        ',5',
      ]) {
        expect(parseRateMicros(bad), isNull, reason: '"$bad"');
      }
    });
  });

  group('ExchangeRate', () {
    test('microsLabel is leesbaar en verliest niets', () {
      expect(_rate('USD', 920000).microsLabel, '0,92');
      expect(_rate('USD', 1).microsLabel, '0,000001');
      expect(_rate('USD', 1500000).microsLabel, '1,50');
      expect(_rate('USD', 892220).microsLabel, '0,89222');
    });

    test(
      'een koers van een week oud of ouder is verouderd, een verse niet',
      () {
        expect(_rate('USD', 1, date: _isoDaysAgo(1)).isStale, isFalse);
        expect(_rate('USD', 1, date: _isoDaysAgo(7)).isStale, isFalse);
        expect(_rate('USD', 1, date: _isoDaysAgo(9)).isStale, isTrue);
      },
    );

    test('een onleesbare peildatum geldt als verouderd, niet als vers', () {
      expect(_rate('USD', 1, date: 'gisteren').isStale, isTrue);
    });
  });

  group('convertAmountMinor', () {
    final rates = {
      'USD': _rate('USD', 920000), // 1 USD = € 0,92
      'GBP': _rate('GBP', 1150000), // 1 GBP = € 1,15
      'JPY': _rate('JPY', 6000), // 1 JPY = € 0,006
    };

    test('dezelfde valuta is de identiteit, ook zonder koers', () {
      expect(convertAmountMinor(1234, _usd, _usd, const {}), 1234);
      expect(convertAmountMinor(1234, _eur, _eur, const {}), 1234);
    });

    test('vreemd → EUR en terug', () {
      expect(convertAmountMinor(10000, _usd, _eur, rates), 9200);
      expect(convertAmountMinor(9200, _eur, _usd, rates), 10000);
    });

    test('twee vreemde valuta lopen via EUR', () {
      // $ 100,00 → € 92,00 → £ 80,00
      expect(convertAmountMinor(10000, _usd, _gbp, rates), 8000);
    });

    test('een valuta zonder decimalen schuift de kleinste eenheid mee', () {
      // ¥ 10.000 × 0,006 = € 60,00
      expect(convertAmountMinor(10000, _jpy, _eur, rates), 6000);
      expect(convertAmountMinor(6000, _eur, _jpy, rates), 10000);
    });

    test('rondt halve omhoog af, nooit stil omlaag', () {
      final half = {'USD': _rate('USD', 500000)}; // 1 USD = € 0,50
      expect(convertAmountMinor(1, _usd, _eur, half), 1); // 0,5 cent → 1
      final low = {'USD': _rate('USD', 400000)};
      expect(convertAmountMinor(1, _usd, _eur, low), 0); // 0,4 cent → 0
    });

    test('een ontbrekende, nul- of verkeerd gelabelde koers geeft null', () {
      expect(convertAmountMinor(100, _usd, _eur, const {}), isNull);
      expect(
        convertAmountMinor(100, _usd, _eur, {'USD': _rate('USD', 0)}),
        isNull,
      );
      expect(
        convertAmountMinor(100, _usd, _eur, {'USD': _rate('GBP', 920000)}),
        isNull,
      );
      // Eén ontbrekende koers van twee is genoeg om niets te verzinnen.
      expect(
        convertAmountMinor(100, _usd, _gbp, {'USD': _rate('USD', 920000)}),
        isNull,
      );
    });

    test('een heel groot bedrag loopt niet over', () {
      const huge = 9000000000000000; // ruim boven 2^53
      final r = {'USD': _rate('USD', 920000)};
      final back = convertAmountMinor(huge, _usd, _eur, r)!;
      expect(
        back,
        (BigInt.from(huge) * BigInt.from(92) ~/ BigInt.from(100)).toInt(),
      );
    });
  });

  group('aanwezigen in meerdere valuta', () {
    const a = CostAssumptions();
    AttendeeInput hourly(int minor, CostCurrency c) =>
        AttendeeInput(amountMinor: minor, period: CostPeriod.hour, currency: c);
    final rates = {'USD': _rate('USD', 920000)};

    test('currenciesNeedingRate noemt de vreemde valuta, nooit EUR', () {
      final needing = currenciesNeedingRate([
        hourly(4000, _eur),
        hourly(5000, _usd),
      ], _eur);
      expect(needing.map((c) => c.code), ['USD']);
    });

    test('een niet-EUR-sessievaluta vraagt zelf ook om een koers', () {
      final needing = currenciesNeedingRate([hourly(4000, _usd)], _usd);
      expect(needing.map((c) => c.code), ['USD']);
      expect(currenciesNeedingRate(const [], _eur), isEmpty);
    });

    test('de som rekent vreemde regels om naar de sessievaluta', () {
      final sum = sumAttendeeRatesMinor(
        [hourly(4000, _eur), hourly(5000, _usd)],
        a,
        _eur,
        rates,
      );
      expect(sum, 4000 + 4600); // $ 50,00 × 0,92
    });

    test(
      'zonder koers telt een vreemde regel niet mee en wordt dat geteld',
      () {
        final inputs = [hourly(4000, _eur), hourly(5000, _usd)];
        expect(sumAttendeeRatesMinor(inputs, a, _eur), 4000);
        expect(unconvertedRateCount(inputs, _eur, const {}), 1);
        expect(unconvertedRateCount(inputs, _eur, rates), 0);
      },
    );
  });

  group('PresentationCostSession met koers', () {
    test('een EUR-sessie heeft geen equivalent', () {
      final s = PresentationCostSession(currency: _eur, hourlyRateMinor: 6000);
      expect(s.eurMinorOf(1000), isNull);
    });

    test('een USD-sessie rekent met de bij de start vastgelegde koers', () {
      final s = PresentationCostSession(
        currency: _usd,
        hourlyRateMinor: 10000,
        eurRate: _rate('USD', 920000),
      );
      expect(s.eurMinorOf(10000), 9200);
      expect(s.finish().eurMinorOf(10000), 9200);
    });

    test('zonder koers verzint de sessie geen EUR-bedrag', () {
      final s = PresentationCostSession(currency: _usd, hourlyRateMinor: 10000);
      expect(s.eurMinorOf(10000), isNull);
      expect(s.finish().eurMinorOf(10000), isNull);
    });
  });

  group('fetchEurRate', () {
    const body =
        '{"amount":1.0,"base":"USD","date":"2026-10-15",'
        '"rates":{"EUR":0.89222}}';

    test('leest het antwoord van Frankfurter exact in', () async {
      Uri? seen;
      final client = MockClient((req) async {
        seen = req.url;
        return http.Response(body, 200);
      });
      final rate = await fetchEurRate('USD', client: client);
      expect(rate, isNotNull);
      expect(rate!.code, 'USD');
      expect(rate.eurMicros, 892220);
      expect(rate.date, '2026-10-15');
      expect(rate.source, 'Frankfurter (ECB)');
      expect(rate.manual, isFalse);
      // Alleen de valutacode gaat de deur uit.
      expect(seen!.host, 'api.frankfurter.dev');
      expect(seen!.queryParameters, {'base': 'USD', 'symbols': 'EUR'});
    });

    test('levert null bij alles wat geen bruikbaar antwoord is', () async {
      Future<ExchangeRate?> with_(http.Response Function() make) =>
          fetchEurRate('USD', client: MockClient((_) async => make()));
      expect(await with_(() => http.Response(body, 404)), isNull);
      expect(await with_(() => http.Response('geen json', 200)), isNull);
      expect(await with_(() => http.Response('[]', 200)), isNull);
      expect(
        await with_(
          () => http.Response(jsonEncode({'date': '2026-10-15'}), 200),
        ),
        isNull,
      );
      expect(
        await with_(
          () => http.Response(
            jsonEncode({
              'date': '2026-10-15',
              'rates': {'GBP': 1.1},
            }),
            200,
          ),
        ),
        isNull,
      );
      expect(
        await with_(
          () => http.Response(
            jsonEncode({
              'date': '2026-10-15',
              'rates': {'EUR': 0},
            }),
            200,
          ),
        ),
        isNull,
      );
    });

    test('volgt geen redirect en kapt een te groot antwoord af', () async {
      var followed = true;
      final client = MockClient((req) async {
        followed = req.followRedirects;
        return http.Response('', 302, headers: {'location': 'https://x.test/'});
      });
      expect(await fetchEurRate('USD', client: client), isNull);
      expect(followed, isFalse);

      final big = MockClient((_) async => http.Response('x' * 20000, 200));
      expect(await fetchEurRate('USD', client: big), isNull);
    });

    test('een netwerkfout is "koers ontbreekt", geen uitzondering', () async {
      final client = MockClient((_) async => throw http.ClientException('af'));
      expect(await fetchEurRate('USD', client: client), isNull);
    });
  });

  group('CurrencyConversionDialog', () {
    Future<Future<Map<String, ExchangeRate>?> Function()> pump(
      WidgetTester tester, {
      List<CostCurrency> currencies = const [_usd],
      Future<ExchangeRate?> Function(String)? fetch,
    }) async {
      Map<String, ExchangeRate>? result;
      var done = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showDialog<Map<String, ExchangeRate>>(
                    context: context,
                    builder: (_) => CurrencyConversionDialog(
                      currencies: currencies,
                      fetchRate: fetch ?? (_) async => null,
                    ),
                  );
                  done = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      return () async {
        expect(done, isTrue, reason: 'de dialoog is nog open');
        return result;
      };
    }

    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    FilledButton confirm(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byKey(const ValueKey('rate-confirm')));

    testWidgets('Bevestigen blijft uit tot elke koers is ingevuld', (
      tester,
    ) async {
      await pump(tester, currencies: const [_usd, _gbp]);
      await open(tester);
      expect(confirm(tester).onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('rate-USD')), '0,92');
      await tester.pump();
      expect(confirm(tester).onPressed, isNull); // GBP nog leeg
      await tester.enterText(find.byKey(const ValueKey('rate-GBP')), '1,15');
      await tester.pump();
      expect(confirm(tester).onPressed, isNotNull);
    });

    testWidgets('een zelf ingevulde koers komt als handmatig terug', (
      tester,
    ) async {
      final result = await pump(tester);
      await open(tester);
      await tester.enterText(find.byKey(const ValueKey('rate-USD')), '0,92');
      await tester.pump();
      expect(find.textContaining('handmatig'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rate-confirm')));
      await tester.pumpAndSettle();
      final got = (await result())!;
      expect(got['USD']!.eurMicros, 920000);
      expect(got['USD']!.manual, isTrue);
    });

    testWidgets('onzin in het veld geeft een leesbare melding, geen koers', (
      tester,
    ) async {
      await pump(tester);
      await open(tester);
      await tester.enterText(find.byKey(const ValueKey('rate-USD')), '0,9,2');
      await tester.pump();
      expect(find.textContaining('Geen geldige koers'), findsOneWidget);
      expect(confirm(tester).onPressed, isNull);
    });

    testWidgets('zonder koers doorgaan levert een lege map, annuleren null', (
      tester,
    ) async {
      var result = await pump(tester);
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('rate-skip')));
      await tester.pumpAndSettle();
      expect(await result(), isEmpty);

      result = await pump(tester);
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('rate-cancel')));
      await tester.pumpAndSettle();
      expect(await result(), isNull);
    });

    testWidgets('ophalen vult het veld, toont de bron en blijft opgehaald', (
      tester,
    ) async {
      final requested = <String>[];
      final result = await pump(
        tester,
        fetch: (code) async {
          requested.add(code);
          return _rate(code, 892220, date: _isoDaysAgo(1));
        },
      );
      await open(tester);
      expect(requested, isEmpty, reason: 'niets gaat uit zonder de knop');
      await tester.tap(find.byKey(const ValueKey('rate-fetch')));
      await tester.pumpAndSettle();
      expect(requested, ['USD']);
      expect(find.textContaining('Frankfurter (ECB)'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('rate-confirm')));
      await tester.pumpAndSettle();
      final got = (await result())!;
      expect(got['USD']!.manual, isFalse);
      expect(got['USD']!.eurMicros, 892220);
    });

    testWidgets('na ophalen telt een aangepaste waarde als handmatig', (
      tester,
    ) async {
      final result = await pump(tester, fetch: (c) async => _rate(c, 892220));
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('rate-fetch')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('rate-USD')), '0,9');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rate-confirm')));
      await tester.pumpAndSettle();
      final got = (await result())!;
      expect(got['USD']!.manual, isTrue);
      expect(got['USD']!.eurMicros, 900000);
    });

    testWidgets('mislukt ophalen meldt het en verzint niets', (tester) async {
      await pump(tester, fetch: (_) async => null);
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('rate-fetch')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ophalen mislukt'), findsOneWidget);
      expect(confirm(tester).onPressed, isNull);
    });

    testWidgets(
      'een verouderde opgehaalde koers wordt als zodanig gemarkeerd',
      (tester) async {
        await pump(
          tester,
          fetch: (c) async => _rate(c, 892220, date: _isoDaysAgo(20)),
        );
        await open(tester);
        await tester.tap(find.byKey(const ValueKey('rate-fetch')));
        await tester.pumpAndSettle();
        expect(find.textContaining('verouderd'), findsOneWidget);
      },
    );
  });
}
