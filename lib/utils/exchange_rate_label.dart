import '../l10n/app_localizations.dart';
import '../models/exchange_rate.dart';

/// De herkomst van een koers als leesbare regel voor dialoog en eindoverzicht
/// (#2438): "Frankfurter (ECB), peildatum 2026-01-14" of "handmatig, peildatum 2026-01-14", met
/// "verouderd" erachter wanneer de peildatum te oud is. Eén plek, zodat beide
/// schermen dezelfde woorden gebruiken en een handmatige koers in élke
/// interfacetaal als handmatig leest.
String exchangeRateProvenance(AppLocalizations l10n, ExchangeRate rate) {
  final origin = rate.manual ? l10n.d('handmatig') : rate.source;
  final stale = rate.isStale ? ' — ${l10n.d('verouderd')}' : '';
  return '$origin, ${l10n.d('peildatum')} ${rate.date}$stale';
}
