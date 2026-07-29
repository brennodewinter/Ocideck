import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T6: een gesprek is wortelgeschikt, geen eigenschap van een presentatie.
/// Wie tijdens een vergadering een ander deck opent, hoort niet uit de
/// vergadering te vallen.
///
/// Bronscan, want dit is niet met een widgettest te vangen: een per tab
/// gescopete sessieprovider zou in elke losse test gewoon werken en pas
/// breken zodra iemand met twee tabbladen van deck wisselt.
void main() {
  test('de vergaderproviders staan niet in de tab-scope van AppShell', () {
    final appShell = File('lib/widgets/app_shell.dart').readAsStringSync();
    for (final provider in [
      'meetingSessionProvider',
      'meetingSessionActiveProvider',
      'meetingsModuleProvider',
      'meetingsModuleEnabledProvider',
      'meetingsModuleRevealProvider',
    ]) {
      expect(
        appShell.contains('$provider.overrideWith'),
        isFalse,
        reason:
            '$provider hoort in de wortel te leven (T6): per tab overriden '
            'zou een lopend gesprek aan één deck vastklinken',
      );
    }
  });

  test('de sessieprovider leest het deck niet en hoeft dus ook nooit '
      'per tab gescoped te worden', () {
    for (final path in [
      'lib/state/meeting_session_provider.dart',
      'lib/state/meetings_module_provider.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        RegExp(
          r'ref\.(?:watch|read|listen)\(\s*(?:deckProvider|editorProvider)',
        ).hasMatch(source),
        isFalse,
        reason:
            '$path leest de per-tab deckstate; dan moet hij in de tab-scope '
            'van AppShell én is T6 (wortelgeschikt) geschonden',
      );
    }
  });
}
