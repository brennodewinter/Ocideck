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
