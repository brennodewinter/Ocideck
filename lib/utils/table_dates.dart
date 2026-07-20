/// Datumherkenning voor tabelcellen, gedeeld door de tabelweergave en haar
/// tests.
///
/// Alleen de ISO-vorm `jjjj-mm-dd` telt als datum. `05-08-2026` is twee
/// verschillende dagen afhankelijk van wie het typte, en een deadline is een
/// slechte plek om te gokken: een cel die niet strikt ISO is, is voor deze
/// laag simpelweg geen datum en wordt nooit gemarkeerd.
library;

final _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// De datum in [cell], of `null` als de cel er geen draagt.
///
/// Verwerpt bestaande-maar-onmogelijke datums (31 februari) door de
/// geconstrueerde [DateTime] terug te vergelijken met wat er stond: `DateTime`
/// rolt zulke waarden stilzwijgend door naar de volgende maand.
DateTime? parseIsoDateCell(String cell) {
  final match = _isoDate.firstMatch(cell.trim());
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

/// Of [cell] een ISO-datum draagt die vóór [asOf] ligt.
///
/// De dag zelf is niet verlopen: een deadline van vandaag is vandaag nog te
/// halen. [asOf] wordt tot op de dag afgekapt, zodat het tijdstip binnen de dag
/// niets uitmaakt.
bool isPastDateCell(String cell, DateTime asOf) {
  final date = parseIsoDateCell(cell);
  if (date == null) return false;
  return date.isBefore(DateTime(asOf.year, asOf.month, asOf.day));
}
