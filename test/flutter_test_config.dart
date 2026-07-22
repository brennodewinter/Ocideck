import 'dart:async';

import 'package:ocideck/state/settings_provider.dart';

/// Draait één keer om de hele testsuite heen (Flutter pikt dit bestand
/// automatisch op voor elke test onder `test/`).
///
/// Sinds een installatie zonder opgeslagen taalkeuze in de taal van het
/// systeem opstart, zou de suite anders van de landinstelling van de machine
/// afhangen: honderden widgettests zoeken Nederlandse knopteksten
/// ("Annuleren", "Importeren via URL"), en op een Engelstalige machine bestaan
/// die niet. Dat is geen echte fout maar wel een rode poort, en erger: op een
/// Nederlandse machine zou hij groen blijven en dus niets bewijzen.
///
/// Nederlands is hier de bronvertaling en daarmee de enige taal waarin élke
/// string bestaat. Een test die juist over taalkeuze gaat, zet hem zelf.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  debugStartupLanguageOverride = 'nl';
  await testMain();
}
