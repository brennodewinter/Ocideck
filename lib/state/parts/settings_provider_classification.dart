// Part of the settings_provider library — see ../settings_provider.dart.
// De classificatie-op-export-schakelaars (verplichting + watermerk); het echte
// werk staat hier top-level zodat het niet meetelt voor het regelplafond van
// SettingsNotifier. Alle imports leven in het hoofdbestand. Verhuisd zonder
// gedragswijziging.
part of '../settings_provider.dart';

/// Eist dat een deck een classificatie draagt voordat het geëxporteerd mag
/// worden, of niet. Puur een exportvoorwaarde; raakt de inhoud niet.
Future<void> _applyRequireClassificationOnExport(
  SettingsNotifier notifier,
  bool enabled,
) {
  notifier.currentState = notifier.currentState.copyWith(
    requireClassificationOnExport: enabled,
  );
  return notifier._persist(
    'setRequireClassificationOnExport',
    (prefs) => prefs.setBool('requireClassificationOnExport', enabled),
  );
}

/// Stempelt de classificatie als watermerk op de geëxporteerde dia's, of niet.
Future<void> _applyClassificationWatermarkEnabled(
  SettingsNotifier notifier,
  bool enabled,
) {
  notifier.currentState = notifier.currentState.copyWith(
    classificationWatermarkEnabled: enabled,
  );
  return notifier._persist(
    'setClassificationWatermarkEnabled',
    (prefs) => prefs.setBool('classificationWatermarkEnabled', enabled),
  );
}
