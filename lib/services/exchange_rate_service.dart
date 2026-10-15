import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/exchange_rate.dart';
import '../utils/log.dart';

/// De ECB-referentiekoersen, gepubliceerd via Frankfurter. Dit is dé
/// enige plek waar de kostenmodus het netwerk op gaat, en alleen op
/// expliciete gebruikersactie — OciDeck raadpleegt geen koersdienst
/// onzichtbaar (#2438).
///
/// Waarom Frankfurter en niet de ECB zelf (afweging #2438): de ECB publiceert
/// dezelfde referentiekoersen als XML op ecb.europa.eu, en dat is de
/// primaire bron. Maar die feed stuurt geen CORS-headers, dus de webbouw kan
/// hem nooit lezen, en hij geeft koersen per euro die we moeten omkeren.
/// Frankfurter is open source, serveert de ECB-reeks met CORS, en draait hier
/// alleen op een knop — met "zelf invullen" en "zonder koers" als
/// uitgangen. Zou je van gedachten veranderen: als Frankfurter ophoudt, een
/// sleutel of betaalmuur krijgt, of als de ECB CORS toevoegt, dan is dit de
/// ene plek die verhuist — de dialoog en het eindoverzicht zien alleen een
/// [ExchangeRate].
const _kFrankfurterBase = 'https://api.frankfurter.dev/v1';

/// Een koersantwoord is een paar honderd bytes; meer dan dit is niet wat we
/// vroegen.
const _kMaxBodyBytes = 8 * 1024;

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
      // Geen redirects: de host is een vaste constante, en een doorverwijzing
      // naar een andere host is dan precies wat we niet willen volgen. Het
      // antwoord is klein; een groter lichaam is geen koers maar ruis, en
      // wordt tijdens het lezen afgekapt in plaats van in geheugen gezet.
      final request = http.Request('GET', uri)..followRedirects = false;
      final streamed = await c
          .send(request)
          .timeout(const Duration(seconds: 10));
      if (streamed.statusCode != 200) return null;
      final bytes = <int>[];
      await for (final chunk in streamed.stream.timeout(
        const Duration(seconds: 10),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > _kMaxBodyBytes) return null;
      }
      return _parseRate(code, utf8.decode(bytes));
    } finally {
      if (own) c.close();
    }
  } on Exception catch (e) {
    // Netwerkfout, time-out of een onleesbaar adres: "koers ontbreekt", geen
    // uitzondering naar de gebruiker. De code van de valuta is geen geheim;
    // het antwoord en het adres van de gebruiker komen er niet in.
    logWarning('fetchEurRate: koers voor $code niet opgehaald', e);
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
  } on FormatException {
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
