import 'package:flutter/foundation.dart';

/// Een valuta zoals de kostenmodus haar gebruikt: ISO-4217-code, symbool en
/// het aantal decimalen van de kleinste eenheid (cent bij EUR, geen bij JPY).
/// Dezelfde tabel stuurt ook de invoer en weergave, dus een valuta die hier
/// niet staat kan nergens gekozen worden.
@immutable
class CostCurrency {
  final String code;
  final String symbol;
  final int decimals;

  const CostCurrency(this.code, this.symbol, this.decimals);
}

/// De valuta waarin een sessietotaal kan worden uitgedrukt. EUR is de
/// standaard (#2435); de rest volgt voor valuta-omrekening (#2438). Niet
/// elke ISO-4217-valuta staat hier — alleen valuta met een bekend symbool en
/// een in deze app verdedigbaar aantal decimalen.
const List<CostCurrency> kCostCurrencies = [
  CostCurrency('EUR', '€', 2),
  CostCurrency('USD', '\$', 2),
  CostCurrency('GBP', '£', 2),
  CostCurrency('CHF', 'CHF ', 2),
  CostCurrency('JPY', '¥', 0),
  CostCurrency('SEK', 'kr ', 2),
  CostCurrency('NOK', 'kr ', 2),
  CostCurrency('DKK', 'kr ', 2),
  CostCurrency('PLN', 'zł', 2),
  CostCurrency('CZK', 'Kč', 2),
];

/// De valuta met [code], of `null` als OciDeck haar niet kent. Een deck met
/// een onbekende code valt terug op EUR bij het presenteren — de sleutel in
/// de front matter blijft wel staan (ze is van de gebruiker).
CostCurrency? costCurrencyByCode(String code) {
  for (final c in kCostCurrencies) {
    if (c.code == code) return c;
  }
  return null;
}

/// Parse een gebruikersbedrag ("75", "75,50", "75.50") naar kleinste
/// eenheden van [currency]. Geeft `null` bij niet-numerieke invoer, negatieve
/// bedragen, meer decimalen dan de valuta kent, of waarden die niet in een
/// 64-bit teller passen.
int? parseAmountMinor(String text, CostCurrency currency) {
  final cleaned = text.trim().replaceAll(currency.symbol.trim(), '').trim();
  if (cleaned.isEmpty) return null;
  if (cleaned.startsWith('-')) return null;
  final match = RegExp(r'^[0-9]+(?:[.,]([0-9]+))?$').firstMatch(cleaned);
  if (match == null) return null;
  final frac = match.group(1) ?? '';
  if (frac.length > currency.decimals) return null;
  final whole = BigInt.tryParse(cleaned.split(RegExp('[.,]')).first);
  if (whole == null) return null;
  final scale = BigInt.from(10).pow(currency.decimals);
  final padded = frac.padRight(currency.decimals, '0');
  final fracPart = padded.isEmpty ? BigInt.zero : BigInt.parse(padded);
  final minor = whole * scale + fracPart;
  if (minor > BigInt.from(1) << 62) return null;
  return minor.toInt();
}

/// Formatteer [minor] kleinste eenheden als `€ 12,34` (decimaalscheiding
/// volgt de UI-taal niet — de valutanotatie is bewust compact en vast,
/// zodat een sessietotaal in een overlay voorspelbaar breed is).
String formatAmountMinor(int minor, CostCurrency currency) {
  final neg = minor < 0;
  final abs = minor.abs();
  final scale = BigInt.from(10).pow(currency.decimals).toInt();
  final whole = abs ~/ scale;
  final frac = (abs % scale).toString().padLeft(currency.decimals, '0');
  final amount = currency.decimals == 0 ? '$whole' : '$whole,$frac';
  return '${neg ? '-' : ''}${currency.symbol}$amount';
}

/// Hoe de kostenindicatie zich gedraagt (#2435).
enum PresentationCostMode {
  /// Uit — niets wordt gemeten of getoond. De afwezige staat: een deck zonder
  /// `ocideck_cost_mode` is kostenloos in de interface.
  off,

  /// "Gewoon" — de kosten staan alleen in het eindoverzicht.
  normal,

  /// "Expliciet" — een lopend sessietotaal tijdens de presentatie én het
  /// eindoverzicht.
  explicit,
}

/// Waar het uurtarief vandaan komt.
enum CostRateInput {
  /// Eén vast uurtarief voor de hele groep, vastgelegd in de instellingen.
  group,

  /// Tarieven per aanwezige, ingevoerd bij de start van de sessie (#2436).
  /// De bedragen zijn sessiegegevens en worden nooit in het deck bewaard.
  attendees,
}

/// De bewaarde kosteninstelling van een presentatie (#2435).
///
/// Round-trips als platte `ocideck_cost_*`-sleutels in de front matter. Wat
/// hier wél staat: modus, invoerroute, groepstarief en valuta — dat zijn
/// voorkeuren van het deck. Wat hier bewust níét staat: individuele tarieven,
/// salarissen en koersmomenten — die horen bij de sessie en verdwijnen zodra
/// de presentatie sluit.
@immutable
class PresentationCostConfig {
  final PresentationCostMode mode;
  final CostRateInput rateInput;

  /// Het groepsuurtarief in kleinste valutaeenheid per uur (bij
  /// [CostRateInput.group]). `0` = niet ingevuld; de sessie zonder tarief
  /// toont dan geen bedrag maar wel de basis, zodat een gemiste invoer
  /// zichtbaar blijft in plaats van een misleidende € 0 te suggereren.
  final int groupHourlyRateMinor;

  /// ISO-4217-valutacode, standaard `'EUR'`.
  final String currencyCode;

  const PresentationCostConfig({
    this.mode = PresentationCostMode.off,
    this.rateInput = CostRateInput.group,
    this.groupHourlyRateMinor = 0,
    this.currencyCode = 'EUR',
  });

  /// De afwezige standaard: kostenmodus uit.
  static const off = PresentationCostConfig();

  bool get isEnabled => mode != PresentationCostMode.off;

  /// De valuta van deze config; onbekende codes vallen terug op EUR.
  CostCurrency get currency =>
      costCurrencyByCode(currencyCode) ?? kCostCurrencies.first;

  PresentationCostConfig copyWith({
    PresentationCostMode? mode,
    CostRateInput? rateInput,
    int? groupHourlyRateMinor,
    String? currencyCode,
  }) {
    return PresentationCostConfig(
      mode: mode ?? this.mode,
      rateInput: rateInput ?? this.rateInput,
      groupHourlyRateMinor: groupHourlyRateMinor ?? this.groupHourlyRateMinor,
      currencyCode: currencyCode ?? this.currencyCode,
    );
  }
}

/// Het groepstarief als gewone decimale voor de front matter (`75` bij JPY,
/// `75.50` bij EUR): leesbaar voor wie het bestand met de hand bewerkt, en
/// zonder valutasymbool zodat de waarde taal- en tooling-neutraal blijft.
String formatCostRateMajor(int minor, CostCurrency currency) {
  final scale = BigInt.from(10).pow(currency.decimals).toInt();
  final whole = minor ~/ scale;
  if (currency.decimals == 0) return '$whole';
  final frac = (minor % scale).toString().padLeft(currency.decimals, '0');
  return '$whole.$frac';
}

/// Kosten in kleinste eenheden voor [elapsed] bij [hourlyRateMinor] kleinste
/// eenheden per uur.
///
/// Rekent in BigInt, nooit in floats: `rate × microseconden / uur` kan in
/// 64-bit overvloeien bij absurde tarieven (1 mrd cent/uur over 100 uur),
/// en binair rekenen zou hele centen verslikken. Afronding is halve omhoog —
/// controleerbaar en zonder periodieke afrondingsbias naar beneden.
int costMinorForElapsed(int hourlyRateMinor, Duration elapsed) {
  if (hourlyRateMinor <= 0 || elapsed <= Duration.zero) return 0;
  final perHour = BigInt.from(Duration.microsecondsPerHour);
  final product =
      BigInt.from(hourlyRateMinor) * BigInt.from(elapsed.inMicroseconds);
  return ((product + perHour ~/ BigInt.two) ~/ perHour).toInt();
}

/// Vertaal de vier `ocideck_cost_*`-sleutels uit de front matter naar een
/// config. Halve of ongeldige invoer valt terug op veilige keuzes: een modus
/// die we niet kennen is uit, een onbekende valuta is EUR, een onleesbaar
/// tarief is 0. Zo kan een handgeschreven sleutel nooit een crash of een
/// stil prijskaartje veroorzaken.
PresentationCostConfig presentationCostFromKeys(Map<String, String> keys) {
  final parsedMode = switch (keys['mode'] ?? '') {
    'normal' => PresentationCostMode.normal,
    'explicit' => PresentationCostMode.explicit,
    _ => PresentationCostMode.off,
  };
  if (parsedMode == PresentationCostMode.off) {
    return PresentationCostConfig.off;
  }
  final parsedInput = switch (keys['input'] ?? '') {
    'attendees' => CostRateInput.attendees,
    _ => CostRateInput.group,
  };
  final parsedCurrency =
      (costCurrencyByCode((keys['currency'] ?? '').toUpperCase()) ??
              kCostCurrencies.first)
          .code;
  final parsedRate =
      parseAmountMinor(
        keys['rate'] ?? '',
        costCurrencyByCode(parsedCurrency)!,
      ) ??
      0;
  return PresentationCostConfig(
    mode: parsedMode,
    rateInput: parsedInput,
    groupHourlyRateMinor: parsedRate,
    currencyCode: parsedCurrency,
  );
}
