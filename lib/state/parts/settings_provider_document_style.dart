// Part of the settings_provider library — see ../settings_provider.dart.
// De documentmodus-stijl (standaardstijl + afdwingen) en de gedeelde
// nullable-string-persist eronder; alle imports leven in het hoofdbestand.
part of '../settings_provider.dart';

/// Schrijf óf wis een nullable string-pref: bij een waarde [prefs.setString],
/// bij `null` [prefs.remove]. Gedeeld door de export-gate-plafonds en de
/// standaard documentstijl — allemaal "kies een sleutel, of zet uit". De
/// [key] is meteen het foutlabel; die is beschrijvend genoeg.
Future<void> _persistNullableString(
  SettingsNotifier notifier,
  String key,
  String? value,
) => notifier._persist(key, (prefs) async {
  if (value == null) {
    await prefs.remove(key);
  } else {
    await prefs.setString(key, value);
  }
});

/// Documentmodus: stel de standaard documentstijl in (een stijlprofielnaam),
/// of `null` voor geen (platte tekst). Puur weergave/export — het raakt geen
/// enkel `.md`-bestand.
Future<void> _applyDocumentDefaultStyle(
  SettingsNotifier notifier,
  String? styleName,
) {
  notifier.currentState = styleName == null
      ? notifier.currentState.copyWith(clearDocumentDefaultStyle: true)
      : notifier.currentState.copyWith(documentDefaultStyle: styleName);
  return _persistNullableString(notifier, 'documentDefaultStyle', styleName);
}

/// Documentmodus: dwing de standaard documentstijl af als huisstijl (negeer
/// per-document `theme:`), of laat elk document zijn eigen stijl kiezen.
Future<void> _applyDocumentStyleEnforced(
  SettingsNotifier notifier,
  bool enforced,
) {
  notifier.currentState = notifier.currentState.copyWith(
    documentStyleEnforced: enforced,
  );
  return notifier._persist(
    'documentStyleEnforced',
    (prefs) => prefs.setBool('documentStyleEnforced', enforced),
  );
}

/// Documentmodus: laat elk hoofdstuk (H1) bij export/afdruk op een nieuwe pagina
/// beginnen, of niet. Puur een export-/afdrukkeuze; raakt geen `.md`-bestand.
Future<void> _applyDocumentChapterPageBreak(
  SettingsNotifier notifier,
  bool enabled,
) {
  notifier.currentState = notifier.currentState.copyWith(
    documentChapterPageBreak: enabled,
  );
  return notifier._persist(
    'documentChapterPageBreak',
    (prefs) => prefs.setBool('documentChapterPageBreak', enabled),
  );
}

/// Documentmodus: stel de maximale schrijfbreedte van de visuele editor in
/// (px), of `null` voor volledige breedte. Feature 2.
Future<void> _applyDocumentEditorMaxWidth(
  SettingsNotifier notifier,
  double? width,
) {
  notifier.currentState = width == null
      ? notifier.currentState.copyWith(clearDocumentEditorMaxWidth: true)
      : notifier.currentState.copyWith(documentEditorMaxWidth: width);
  // `null` (volledige breedte) wordt als 0 weggeschreven, niet als een
  // verwijderde sleutel: een ontbrekende sleutel is "nooit gekozen" en leest bij
  // het opstarten terug als de standaard 1100. Wie volledige breedte koos, kreeg
  // na een herstart stilzwijgend weer een smalle editor.
  return notifier._persist(
    'documentEditorMaxWidth',
    (prefs) => prefs.setDouble('documentEditorMaxWidth', width ?? 0),
  );
}

/// De opgeslagen schrijfbreedte terug: `0` betekent volledige breedte (zie
/// [_applyDocumentEditorMaxWidth]), een ontbrekende sleutel betekent "nog nooit
/// gekozen" en krijgt de standaard van 1100 px.
double? _readDocumentEditorMaxWidth(SharedPreferences prefs) =>
    switch (prefs.getDouble('documentEditorMaxWidth')) {
      null => 1100,
      <= 0 => null,
      final width => width,
    };

/// Documentmodus: stel de paginamaat voor export in (ISO-216). Feature 3.
Future<void> _applyDocumentPageSize(
  SettingsNotifier notifier,
  PageSizeSpec spec,
) {
  notifier.currentState = notifier.currentState.copyWith(
    documentPageSize: spec,
  );
  return notifier._persist(
    'documentPageSize',
    (prefs) => prefs.setString('documentPageSize', spec.id),
  );
}

/// Documentmodus: stel de paginamarges voor export in. Feature 3.
Future<void> _applyDocumentPageMargins(
  SettingsNotifier notifier,
  PageMargins margins,
) {
  notifier.currentState = notifier.currentState.copyWith(
    documentPageMargins: margins,
  );
  return notifier._persist(
    'documentPageMargins',
    (prefs) => prefs.setString('documentPageMargins', margins.id),
  );
}
