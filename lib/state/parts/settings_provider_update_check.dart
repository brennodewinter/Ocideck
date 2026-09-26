// Part of the settings_provider library — see ../settings_provider.dart.
// Split out for navigability; alle imports leven in het hoofdbestand.
part of '../settings_provider.dart';

/// `updateChecksEnabled`: de enige standaard-uit-schakelaar die zélf uitgaand
/// verkeer veroorzaakt (één ping per dag naar de forge). Hij staat daarom uit
/// tenzij de gebruiker hem aanzet. De handmatige controle op het Over-tabblad
/// valt hier niet onder — die is zelf de actie van de gebruiker.
Future<void> _applyUpdateChecksEnabled(
  SettingsNotifier notifier,
  bool enabled,
) {
  notifier.currentState = notifier.currentState.copyWith(
    updateChecksEnabled: enabled,
  );
  return notifier._persist(
    'updateChecksEnabled',
    (prefs) => prefs.setBool('updateChecksEnabled', enabled),
  );
}
