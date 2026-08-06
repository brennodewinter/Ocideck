/// Taalbewuste getalnotatie voor tabelcellen — headless, zonder Flutter.
///
/// De celinhoud blijft rauw in de .md (bijv. `1234.5`); deze helper formatteert
/// de waarde bij het renderen volgens de deck-taal. Een cel die niet als getal
/// te parsen is blijft ongewijzigd — de functie faalt stil, zoals de codec dat
/// ook doet bij onherkenbare invoer.
library;

import 'package:intl/intl.dart';

/// Of [value] door [formatTableCellNumber] als getal geformatteerd zou worden.
/// Gebruikt door de editor om de toggle te tonen.
bool isParseableNumber(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  return double.tryParse(trimmed) != null;
}

/// Formatteer [value] als getal volgens [locale] (bijv. `nl`, `en`). Geeft de
/// oorspronkelijke waarde terug als het geen getal is — de cel blijft dan wat
/// de auteur typte. [locale] mag leeg zijn (dan geen notatie).
String formatTableCellNumber(String value, String locale) {
  if (locale.isEmpty) return value;
  final trimmed = value.trim();
  final n = double.tryParse(trimmed);
  if (n == null) return value;
  final formatted = NumberFormat.decimalPattern(locale).format(n);
  // Behoud lege ruimte rond het getal niet — de celrenderer padding doet dat.
  return formatted;
}
