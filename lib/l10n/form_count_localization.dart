// De zin bij een teller van een formulierveld ("Woorden: 90 (minimaal 150)").
//
// De eenheid is een zelfstandig naamwoord in het meervoud dat als *label* staat,
// niet in een zin: "{eenheid}: {actual} (minimaal {min})". Zo hoeft geen taal een
// getal te verbuigen — "Woorden: 90" is overal grammaticaal, en de vertaler
// bepaalt de volgorde. Zelfde keuze als de berichtencatalogus (`form_issue_localization.dart`).

import 'package:ocideck_form_core/ocideck_form_core.dart';

import 'app_localizations.dart';

String formCountLabel(AppLocalizations l10n, FormCount count) {
  final unit = switch (count.unit) {
    FormCountUnit.words => l10n.d('Woorden'),
    FormCountUnit.chars => l10n.d('Tekens'),
    FormCountUnit.items => l10n.d('Punten'),
    FormCountUnit.choices => l10n.d('Keuzes'),
    FormCountUnit.rows => l10n.d('Rijen'),
    FormCountUnit.images => l10n.d('Foto’s'),
  };
  // `formCounts` geeft alleen een teller als er minstens één grens is; zonder
  // grens valt een teller in de minimaal-zin, en dat bestaat dus niet.
  final template = switch ((count.min, count.max)) {
    (_?, _?) => l10n.d('{eenheid}: {actual} (minimaal {min}, maximaal {max})'),
    (null, _?) => l10n.d('{eenheid}: {actual} (maximaal {max})'),
    _ => l10n.d('{eenheid}: {actual} (minimaal {min})'),
  };
  return template
      .replaceAll('{eenheid}', unit)
      .replaceAll('{actual}', '${count.actual}')
      .replaceAll('{min}', '${count.min ?? ''}')
      .replaceAll('{max}', '${count.max ?? ''}');
}
