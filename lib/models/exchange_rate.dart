import 'package:flutter/foundation.dart';

import 'presentation_cost.dart';

/// Eén vastgelegde wisselkoers voor de kostenmodus (#2438): hoeveel euro één
/// eenheid van de vreemde valuta waard is. De koers staat in miljoensten
/// (`eurMicros` = EUR × 1.000.000) zodat het omrekenen geheel in [BigInt]
/// kan — een float zou hele centen kunnen verslikken.
///
/// Sessiegegeven: de koers wordt bij de start van de sessie vastgelegd en
/// nooit bewaard. [source], [date] en [manual] maken de herkomst voor de
/// gebruiker controleerbaar ("Frankfurter (ECB), peildatum 2026-01-14" of
/// "handmatig" — dat laatste woord komt uit de vertaling, niet uit dit object).
@immutable
class ExchangeRate {
  /// ISO-4217-code van de vreemde valuta — nooit `'EUR'` zelf.
  final String code;

  /// Euro per één eenheid van [code], in miljoensten. Een koers van
  /// "1 USD = € 0,92" is `920000`.
  final int eurMicros;

  /// De naam van de dienst waar de koers vandaan komt — bijvoorbeeld
  /// `'Frankfurter (ECB)'`, een eigennaam en dus niet te vertalen. Leeg bij een
  /// [manual]e koers: het label daarvoor hoort bij de interfacetaal.
  final String source;

  /// De peildatum van de bron als ISO-datum (`2026-01-14`). Bij een
  /// handmatige koers is dit de dag van invoer.
  final String date;

  /// `true` als de gebruiker de koers zelf heeft ingevoerd.
  final bool manual;

  const ExchangeRate({
    required this.code,
    required this.eurMicros,
    required this.source,
    required this.date,
    required this.manual,
  });

  /// De ECB publiceert op werkdagen een nieuwe referentiekoers; een koers
  /// ouder dan een week wordt als verouderd gemarkeerd — zichtbaar, want een
  /// stille oude koers lijkt dan actueel.
  bool get isStale {
    final then = DateTime.tryParse(date);
    if (then == null) return true;
    return DateTime.now().difference(then).inDays > 7;
  }

  /// De koers als kommagetal met zes decimalen, voor de invoercontrole.
  String get microsLabel {
    final whole = eurMicros ~/ 1000000;
    final frac = (eurMicros % 1000000).toString().padLeft(6, '0');
    return '$whole,${frac.replaceAll(RegExp(r'0+$'), '').padRight(2, '0')}';
  }
}

/// Parse een gebruikerskoers ("0,92" / "0.92") naar EUR-miljoensten per
/// eenheid. `null` bij rotte, negatieve of nul-invoer — meer dan zes
/// decimalen kan de koersweergave niet eerlijk terugspiegelen.
int? parseRateMicros(String text) {
  final clean = text.trim();
  final match = RegExp(r'^([0-9]+)(?:[.,]([0-9]{1,6}))?$').firstMatch(clean);
  if (match == null) return null;
  final whole = int.parse(match.group(1)!);
  final frac = (match.group(2) ?? '').padRight(6, '0');
  final micros = whole * 1000000 + int.parse(frac);
  return micros > 0 ? micros : null;
}

/// Reken [minor] kleinste eenheden van [from] om naar kleinste eenheden van
/// [to], via EUR als spil: `bedrag → EUR → doelvaluta`. Een koers in
/// [rates] legt dus zowel `USD → EUR` als `EUR → USD` vast.
///
/// Geeft `null` wanneer een benodigde koers ontbreekt — geen bedrag tonen is
/// eerlijker dan een verzonnen omrekening (#2438). Afronding is halve omhoog,
/// dezelfde regel als de tijdskosten.
int? convertAmountMinor(
  int minor,
  CostCurrency from,
  CostCurrency to,
  Map<String, ExchangeRate> rates,
) {
  if (from.code == to.code) return minor;
  final million = BigInt.from(1000000);
  final rf = from.code == 'EUR'
      ? million
      : _microsOf(rates[from.code], from.code);
  final rt = to.code == 'EUR' ? million : _microsOf(rates[to.code], to.code);
  if (rf == null || rt == null) return null;
  final numerator = BigInt.from(minor) * rf * BigInt.from(10).pow(to.decimals);
  final denominator = rt * BigInt.from(10).pow(from.decimals);
  return ((numerator + denominator ~/ BigInt.two) ~/ denominator).toInt();
}

BigInt? _microsOf(ExchangeRate? rate, String code) {
  if (rate == null || rate.code != code || rate.eurMicros <= 0) return null;
  return BigInt.from(rate.eurMicros);
}
