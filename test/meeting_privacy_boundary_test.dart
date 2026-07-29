import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// De privacygrens van de vergaderlaag, als bronscan — in de geest van
/// `provider_scope_test.dart`: de volgende overtreding valt bij het testen,
/// niet pas bij een lek.
///
/// Twee beloften worden hier vastgeklonken:
///
///   1. **Er kan geen byte het netwerk op** (T8, en de opdracht van deze
///      laag). Niets onder `lib/meetings/` importeert een netwerk- of
///      platformlaag; de enige weg naar buiten is een adapter die er nog
///      niet is.
///   2. **De link en het toegangsbewijs staan niet in inspecteerbare
///      toestand** (T5, §8.1). `meeting_state.dart` kent geen `Uri` en geen
///      token; de uitnodiging leeft in een privéveld van de notifier.
void main() {
  List<File> dartFilesUnder(String path) => Directory(path)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('lib/meetings heeft geen enkele route naar netwerk of platform', () {
    // Wat hier verboden is: alles waarmee een verbinding te openen valt of
    // waarmee platformcode aan te roepen is. `dart:async` en `dart:collection`
    // blijven gewoon toegestaan.
    final forbidden = RegExp(
      r'''import\s+['"](dart:io|dart:html|dart:js_interop|dart:ffi|'''
      r'''package:http|package:web|package:dio|package:flutter/services)''',
    );
    final offenders = <String>[];
    for (final file in dartFilesUnder('lib/meetings')) {
      final match = forbidden.firstMatch(file.readAsStringSync());
      if (match != null) {
        offenders.add('${file.path}: ${match.group(1)}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'De vergaderlaag hoort aanbieder-neutraal en netwerkloos te zijn; '
          'een adapter met een echte verbinding krijgt zijn eigen map en zijn '
          'eigen vrijgavepoorten (COLLABORATION.md §7.1.4): $offenders',
    );
  });

  test('lib/meetings gebruikt Flutter alleen waar dat hardop mag', () {
    // De laag is met opzet vrij van Flutter; alleen het register mag
    // `kDebugMode` lezen om de nep-adapter uit een uitgebrachte app te houden.
    final flutterImport = RegExp(r'''import\s+['"]package:flutter''');
    final offenders = <String>[];
    for (final file in dartFilesUnder('lib/meetings')) {
      if (file.path.endsWith('lib/meetings/meeting_registry.dart')) continue;
      if (flutterImport.hasMatch(file.readAsStringSync())) {
        offenders.add(file.path);
      }
    }
    expect(offenders, isEmpty);
  });

  test('meeting_state.dart kent geen link, token of Uri (T5, §8.1)', () {
    // De scan kijkt naar de code en niet naar het commentaar: dat commentaar
    // legt juist úit waarom deze woorden verboden zijn, en mag ze dus noemen.
    final code = File('lib/meetings/meeting_state.dart')
        .readAsLinesSync()
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    for (final verboden in [
      'Uri',
      'token',
      'Token',
      'credential',
      'Credential',
      'invitation',
      'meeting_link.dart',
    ]) {
      expect(
        code.contains(verboden),
        isFalse,
        reason:
            '`$verboden` hoort niet in de inspecteerbare vergadertoestand; '
            'de uitnodiging en het toegangsbewijs leven in privévelden van '
            'de aanroeper en worden bij het verlaten gewist',
      );
    }
  });

  test('de notifier houdt de uitnodiging in een privéveld', () {
    final source = File(
      'lib/state/meeting_session_provider.dart',
    ).readAsStringSync();
    // Het veld bestaat en is privé…
    expect(source, contains('MeetingLinkMatch? _link'));
    // …en er is geen getter of veld dat hem naar buiten geeft.
    expect(
      RegExp(r'MeetingLinkMatch\??\s+get\s+(?!_)').hasMatch(source),
      isFalse,
      reason: 'een publieke getter zou de uitnodiging inspecteerbaar maken',
    );
  });
}
