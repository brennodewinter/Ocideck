import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/dialogs/new_document_dialog.dart';
import 'package:ocideck/widgets/shell/new_document_action.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'support/pump_until.dart';

/// De actie achter 'Nieuw document' (#2177): op desktop opent hij de
/// aanmaakdialoog en roept de provider aan met de gekozen plek — annuleren
/// maakt niets aan, een mislukte aanmaak meldt een fout. De schijfaanmaak
/// zelf loopt via `debugNewDocumentRunner`: echte `File.create` beantwoordt
/// de fake klok van flutter_test niet, en die tak dekt
/// document_new_and_save_as_test.dart al op providerniveau.
Widget _host() {
  AppLocalizations.setActiveLanguageCode('nl');
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<Object?>>[
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => ElevatedButton(
            onPressed: () => newDocumentFromDialog(context),
            child: const Text('nieuw'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late Directory home;

  setUp(() {
    home = Directory.systemTemp.createTempSync('newdoc_action');
    SharedPreferences.setMockInitialValues({
      'storageConnections': StorageConnection.encodeList([
        LocalConnection(id: 'lok', name: 'Werkmap', path: home.path),
      ]),
    });
    debugNewDocumentRunner = null;
  });

  tearDown(() {
    debugNewDocumentRunner = null;
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  /// Wacht tot de bibliotheek uit prefs geladen is — de dialoog leest die
  /// lijst bij het openen. `pumpUntil` wisselt echte tijd (waar de
  /// SettingsNotifier vooruitkomt) af met een frame, en faalt pas als het
  /// er nooit komt.
  Future<void> waitForLibraries(WidgetTester tester) async {
    final container = ProviderScope.containerOf(
      tester.element(find.text('nieuw')),
    );
    await pumpUntil(
      tester,
      () => container.read(settingsProvider).libraries.isNotEmpty,
      reason: 'bibliotheek uit prefs niet geladen',
    );
  }

  testWidgets('naam + map roept de aanmaak aan met het volledige pad', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    String? createdPath;
    debugNewDocumentRunner = (path) async {
      createdPath = path;
      return true;
    };

    await tester.pumpWidget(_host());
    await waitForLibraries(tester);

    await tester.tap(find.text('nieuw'));
    await tester.pumpAndSettle();
    expect(find.byType(NewDocumentDialog), findsOneWidget);
    expect(find.text('Werkmap'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'actie doc');
    await tester.tap(find.text('Aanmaken'));
    await tester.pumpAndSettle();

    expect(find.byType(NewDocumentDialog), findsNothing);
    expect(createdPath, p.join(home.path, 'actie_doc.md'));
  });

  testWidgets('mislukte aanmaak meldt een fout in plaats van stilte', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    debugNewDocumentRunner = (path) async => false;

    await tester.pumpWidget(_host());
    await waitForLibraries(tester);

    await tester.tap(find.text('nieuw'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'actie doc');
    await tester.tap(find.text('Aanmaken'));
    await tester.pumpAndSettle();

    expect(find.text('Kon het bestand niet aanmaken.'), findsOneWidget);
  });

  testWidgets('annuleren roept de aanmaak niet aan', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var called = false;
    debugNewDocumentRunner = (path) async {
      called = true;
      return true;
    };

    await tester.pumpWidget(_host());
    await waitForLibraries(tester);

    await tester.tap(find.text('nieuw'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(home.listSync(), isEmpty);
  });
}
