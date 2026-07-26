import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/trash_service.dart';
import 'package:ocideck/widgets/dialogs/duplicate_cleanup_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pump_until.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'opruimen verplaatst een kopie en beschermt de laatste',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync('ocideck_cleanupdlg_');
      addTearDown(() {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final a = File(p.join(temp.path, 'A.md'))..writeAsStringSync('# x');
      final b = File(p.join(temp.path, 'kopie', 'A.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync('# x');
      final trash = TrashService(osHome: () => temp.path);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: DuplicateCleanupDialog(
                groups: [
                  CleanupGroup(title: 'A', paths: [a.path, b.path]),
                ],
                homeDir: temp.path,
                trashService: trash,
              ),
            ),
          ),
        ),
      );
      // Echte bestand-I/O (stat, verplaatsen) komt onder FakeAsync alleen klaar
      // binnen runAsync. Wachten tot de rijen er zíjn — dat is waarneembaar, in
      // tegenstelling tot de 50 ms die hier stond.
      final buttons = find.byIcon(Icons.delete_outline);
      await pumpUntil(
        tester,
        () => buttons.evaluate().length == 2,
        reason: 'de twee kopieën verschenen niet als rijen',
      );

      // Twee rijen met elk een prullenbakknop, beide actief.
      expect(buttons, findsNWidgets(2));

      await tester.tap(buttons.last);
      // Twee dingen om op te wachten, en ze zijn niet hetzelfde: eerst is het
      // bestand van schijf, dáárna verwerkt de setState-continuatie dat in de
      // boom. Alleen op het bestand wachten liet de rij nog actief staan; vandaar
      // dat hier eerder een extra venster van 100 ms plus een pump van 300 ms
      // achteraan stond. Beide voorwaarden expliciet is korter én zeker.
      await pumpUntil(
        tester,
        () => !b.existsSync(),
        reason: 'de kopie werd nooit naar de prullenbak verplaatst',
      );
      await pumpUntil(
        tester,
        () {
          if (buttons.evaluate().length != 1) return false;
          final row = find
              .ancestor(of: buttons, matching: find.byType(IconButton))
              .evaluate();
          return row.length == 1 &&
              (row.single.widget as IconButton).onPressed == null;
        },
        reason: 'de laatste kopie werd niet beschermd nadat de andere weg was',
      );

      // De tweede kopie is verplaatst; het origineel staat er nog.
      expect(b.existsSync(), isFalse);
      expect(a.existsSync(), isTrue);

      // De overgebleven (laatste) kopie is niet meer te verwijderen.
      final remaining = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.delete_outline),
          matching: find.byType(IconButton),
        ),
      );
      expect(remaining.onPressed, isNull);
      // De opruimdialoog verplaatst de kopie via TrashService naar de
      // prullenbak, en die bestaat op Windows niet (zie trash_service_test).
      // Recycle Bin-integratie is een aparte feature, geen bug (#880).
    },
    skip: Platform.isWindows ? 'geen prullenbak op Windows (feature)' : false,
  );
}
