import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/trash_service.dart';
import 'package:ocideck/widgets/dialogs/duplicate_cleanup_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Pompt frames binnen [WidgetTester.runAsync] tot [tot] waar is, of tot de
/// tijdsgrens verstrijkt.
///
/// Het alternatief — een vaste `Future.delayed` — wacht een gok in plaats van
/// een uitkomst. Dat haalt het op een rustige machine en niet onder een volle
/// `make check`, en dan faalt een test die niets mankeert. Los draait hij dan
/// gewoon groen, dus je zoekt op de verkeerde plek.
Future<void> _wachtTot(
  WidgetTester tester,
  bool Function() tot, {
  Duration grens = const Duration(seconds: 10),
}) async {
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(grens);
    while (!tot() && DateTime.now().isBefore(deadline)) {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  });
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('opruimen verplaatst een kopie en beschermt de laatste', (
    tester,
  ) async {
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
    // binnen runAsync. Wachten op de uitkomst in plaats van op de klok: hier
    // stonden vaste slaapjes van 50 en 100 ms.
    await _wachtTot(
      tester,
      () => find.byIcon(Icons.delete_outline).evaluate().length == 2,
    );

    // Twee rijen met elk een prullenbakknop, beide actief.
    final buttons = find.byIcon(Icons.delete_outline);
    expect(buttons, findsNWidgets(2));

    await tester.tap(buttons.last);
    await tester.pump();
    await _wachtTot(tester, () => !b.existsSync());
    await tester.pump(const Duration(milliseconds: 300));

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
  });
}
