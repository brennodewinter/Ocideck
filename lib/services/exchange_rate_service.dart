import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/exchange_rate.dart';

/// De ECB-referentiekoersen, gepubliceerd via Frankfurter. Dit is dé
/// enige plek waar de kostenmodus het netwerk op gaat, en alleen op
/// expliciete gebruikersactie — OciDeck raadpleegt geen koersdienst
/// onzichtbaar (#2438).
const _kFrankfurterBase = 'https://api.frankfurter.dev/v1';

const _kSourceLabel = 'Frankfurter (ECB)';

/// Haalt de EUR-koers van één vreemde valuta op: "1 [code] = € …".
///
/// Geeft `null` bij een netwerkfout, een onbekende valuta of een antwoord
/// dat niet te lezen is — de roeper toont dan "koers ontbreekt" in plaats
/// van een verzonnen waarde. `client` en `baseUrl` zijn alleen voor tests.
Future<ExchangeRate?> fetchEurRate(
  String code, {
  http.Client? client,
  String? baseUrl,
}) async {
  final uri = Uri.parse(
    '${baseUrl ?? _kFrankfurterBase}/latest?base=$code&symbols=EUR',
  );
  try {
    final own = client == null;
    final c = client ?? http.Client();
    try {
      final res = await c.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      return _parseRate(code, res.body);
    } finally {
      if (own) c.close();
    }
  } catch (_) {
    return null;
  }
}

/// `{ "amount":1, "base":"USD", "date":"2026-01-14", "rates":{"EUR":0.86} }`
/// → een [ExchangeRate]. De koers komt als JSON-getal; `toString` levert een
/// decimale notatie die [parseRateMicros] exact vastlegt.
ExchangeRate? _parseRate(String code, String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  final rates = decoded['rates'];
  final date = decoded['date'];
  if (rates is! Map || date is! String) return null;
  final eur = rates['EUR'];
  if (eur is! num) return null;
  final micros = parseRateMicros(eur.toString());
  if (micros == null) return null;
  return ExchangeRate(
    code: code,
    eurMicros: micros,
    source: _kSourceLabel,
    date: date,
    manual: false,
  );
}
