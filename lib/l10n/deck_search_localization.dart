import '../utils/deck_text_search.dart';
import 'app_localizations.dart';

/// Gelijke woorden in twee cellen of kolommen blijven als resultaat te onderscheiden.
String deckSearchLocation(AppLocalizations l10n, DeckTextMatch match) {
  final label = l10n.d(match.fieldLabel);
  final parts = match.fieldId.split('.');
  if (parts.length == 3 && parts.first == 'tableRows') {
    final row = int.tryParse(parts[1]);
    final column = int.tryParse(parts[2]);
    if (row != null && column != null) {
      return '$label · ${l10n.d('Rij')} ${row + 1} · ${l10n.d('Kolom')} ${column + 1}';
    }
  }
  if (match.fieldId == 'columnTitle1') {
    return '$label · ${l10n.d('Links')}';
  }
  if (match.fieldId == 'columnTitle2' || match.fieldId == 'imageCaption2') {
    return '$label · ${l10n.d('Rechts')}';
  }
  if (parts.length >= 2) {
    final index = int.tryParse(parts[1]);
    if (index != null) return '$label · ${index + 1}';
  }
  return label;
}
