import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/widgets/dialogs/settings/git_form.dart';
import 'package:ocideck/widgets/dialogs/settings/git_panel.dart';

/// Het git-paneel, los van het instellingenvenster. Zie
/// settings_s3_panel_test.dart voor waarom dat losstaan de winst is (#631).
void main() {
  late GitForm form;
  var changes = 0;

  setUp(() {
    form = GitForm();
    changes = 0;
  });
  tearDown(() => form.dispose());

  Future<void> show(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GitPanel(
                form: form,
                confirmCertificate:
                    ({
                      required origin,
                      required host,
                      required allowPrivate,
                    }) async => null,
                onChanged: () => changes++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders without the settings dialog around it', (tester) async {
    await show(tester);
    expect(find.text('GIT-REPOSITORY'), findsOneWidget);
    expect(find.text('Personal access token'), findsOneWidget);
  });

  testWidgets('the token scope help follows the chosen forge', (tester) async {
    // Proactief, niet pas nadat een test faalt: de scope heet per forge anders,
    // en je hoeft het niet eerst mis te hebben om te weten wat je aanvinkt.
    await show(tester);
    expect(find.textContaining('Gitea en Forgejo'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<GitProvider>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GitLab').last);
    await tester.pumpAndSettle();

    expect(form.provider, GitProvider.gitlab);
    expect(find.textContaining('read_repository'), findsOneWidget);
    expect(changes, greaterThan(0));
  });

  testWidgets('trusting an internal server voids the previous result', (
    tester,
  ) async {
    form
      ..testOk = true
      ..testMessage = 'Verbinding gelukt.';
    await show(tester);
    expect(find.text('Verbinding gelukt.'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    // De vlag bepaalt of de host überhaupt gebeld mag worden; een oude groene
    // vink bij een nieuwe regel is erger dan geen vink.
    expect(form.trusted, true);
    expect(form.testOk, isNull);
    expect(find.text('Verbinding gelukt.'), findsNothing);
  });

  testWidgets('an unconfigured repo is refused before any network call', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('Verbinding testen'));
    await tester.pumpAndSettle();

    expect(
      find.text('Vul server-URL, eigenaar en repository in'),
      findsOneWidget,
    );
    expect(form.testOk, false);
  });
}
