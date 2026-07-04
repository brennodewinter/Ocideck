import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/trash_service.dart';
import 'package:ocideck/widgets/dialogs/duplicate_cleanup_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

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
    // Echte bestand-I/O (stat, verplaatsen) komt onder FakeAsync alleen
    // klaar binnen runAsync; daarna gewone pumps voor de frames.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    // Twee rijen met elk een prullenbakknop, beide actief.
    final buttons = find.byIcon(Icons.delete_outline);
    expect(buttons, findsNWidgets(2));

    await tester.tap(buttons.last);
    await tester.pump();
    for (var i = 0; i < 10 && b.existsSync(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    // Nog één echt-async venster zodat de setState-continuatie na de
    // geslaagde verplaatsing ook verwerkt is.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
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
