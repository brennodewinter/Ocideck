library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

/// Een presentatie op de eigen webserver, gevonden via de autoindex.
typedef WebDeckEntry = ({String name, String url});

/// De naam van het config-bestand dat de beheerder op de server plaatst om de
/// presentatiemap aan te wijzen. Staat op de wortel van dezelfde origin als
/// de app — zie HOSTING.md §7.
const _kConfigFileName = 'ocideck-web-config.json';

/// Haal het config-bestand op dat de beheerder op de wortel van de app
/// plaatst, of null als het ontbreekt/onleesbaar is — afwezigheid is de
/// verwachte toestand, geen fout om te loggen.
Future<Map<String, Object?>?> _fetchWebConfig(http.Client client) async {
  try {
    final r = await client.get(Uri.base.resolve(_kConfigFileName));
    if (r.statusCode != 200) return null;
    final json = jsonDecode(r.body);
    if (json is! Map) return null;
    return Map<String, Object?>.from(json);
  } on Exception {
    return null;
  }
}

/// Haal het pad naar de presentatie-map op uit het config-bestand op de
/// server. Geeft null als het bestand niet bestaat, niet leesbaar is, of geen
/// geldig `decksPath` bevat — de feature staat dan uit.
Future<String?> _fetchDecksPath(http.Client client) async {
  final path = (await _fetchWebConfig(client))?['decksPath'];
  if (path is! String || path.isEmpty) return null;
  return path;
}

/// De origins die Markdown via postMessage mogen aanbieden (#2827), uit
/// `trustedMessageOrigins` in hetzelfde config-bestand. Leeg = de opt-in
/// staat uit op config-niveau; elke site die OciDeck mag insluiten mag
/// dan vragen — de gebruiker beslist alsnog expliciet per overdracht.
Future<List<String>> fetchTrustedMessageOrigins({http.Client? client}) async {
  if (!kIsWeb) return const [];
  final c = client ?? http.Client();
  try {
    final value = (await _fetchWebConfig(c))?['trustedMessageOrigins'];
    if (value is! List) return const [];
    return [
      for (final e in value)
        if (e is String && e.trim().isNotEmpty) e.trim(),
    ];
  } finally {
    if (client == null) c.close();
  }
}

/// Parse de HTML van een Apache/Nginx autoindex-pagina en geef alle `.md`-
/// links terug, met hun URL volledig opgelost tegen [baseUrl].
///
/// Zowel Apache (`Options +Indexes`) als Nginx (`autoindex on`) produceren
/// `<a href="naam.md">`-links; de parser zoekt alle `<a>`-tags met een href
/// die op `.md` eindigt. Submappen worden niet gevolgd — de autoindex is plat,
/// en een diepere scan hoort bij de desktop-zoekfunctie.
List<WebDeckEntry> parseAutoindexHtml(String html, String baseUrl) {
  final doc = html_parser.parse(html);
  final base = Uri.tryParse(baseUrl);
  if (base == null || !base.hasScheme) return const [];
  final entries = <WebDeckEntry>[];
  final seen = <String>{};
  for (final a in doc.querySelectorAll('a')) {
    final href = a.attributes['href'];
    if (href == null) continue;
    if (!href.toLowerCase().endsWith('.md')) continue;
    final resolved = base.resolve(href);
    final url = resolved.toString();
    if (!seen.add(url)) continue;
    final name = resolved.pathSegments.isEmpty
        ? href
        : resolved.pathSegments.last;
    entries.add((name: name, url: url));
  }
  // Sorteer alfabetisch op naam — de autoindex volgt de server-eigen volgorde
  // (Apache naam, Nginx naam), die niet de volgorde is die een gebruiker zoekt.
  entries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return entries;
}

/// Haal de lijst presentaties op van de eigen webserver. Alleen op web; op
/// andere platforms is de lijst altijd leeg. De beheerder configureert het pad
/// via een statisch config-bestand op de server (zie HOSTING.md §7).
///
/// Alles wat misgaat (geen config, geen autoindex, netwerkfout) leidt tot een
/// lege lijst — de feature is opt-in en afwezigheid is geen fout.
Future<List<WebDeckEntry>> fetchWebDeckIndex({http.Client? client}) async {
  if (!kIsWeb) return const [];
  final c = client ?? http.Client();
  try {
    final path = await _fetchDecksPath(c);
    if (path == null) return const [];
    final indexUrl = Uri.base.resolve(path);
    final r = await c.get(indexUrl);
    if (r.statusCode != 200) return const [];
    return parseAutoindexHtml(r.body, indexUrl.toString());
  } on Exception {
    // Netwerkfout of de autoindex staat uit — de feature is opt-in en
    // afwezigheid is geen fout.
    return const [];
  } finally {
    if (client == null) c.close();
  }
}

/// De lijst presentaties op de eigen webserver. `autoDispose` zodat een
/// gesloten welkomstscherm de cache niet vasthoudt. Op niet-web platforms is
/// de lijst altijd leeg.
final webDeckIndexProvider = FutureProvider.autoDispose<List<WebDeckEntry>>((
  ref,
) async {
  return fetchWebDeckIndex();
});
