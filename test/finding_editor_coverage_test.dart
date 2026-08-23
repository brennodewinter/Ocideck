import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/widgets/editors/_editor_field.dart';
import 'package:ocideck/widgets/editors/finding_editor.dart';
import 'package:ocideck/widgets/editors/markdown_editor_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Field-editing coverage for the pentest [FindingEditor] header: every text
/// field round-trips through [FindingSpec] into the emitted slide, the derived
/// CVSS read-out reacts to the vector, and the retest dropdown drives its note
/// field. The editor embeds AI-suggest controls (ConsumerWidgets reading the
/// settings provider), so it is hosted in a [ProviderScope] with a mocked
/// SharedPreferences store.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocalizations.setActiveLanguageCode('nl');
  });
  tearDown(() => AppLocalizations.setActiveLanguageCode('nl'));

  // A well-formed CVSS 4.0 vector that scores 9.3 (Critical).
  const criticalVector =
      'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N';

  Widget host(Slide slide, void Function(Slide) onUpdate) => ProviderScope(
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: FindingEditor(
          slide: slide,
          onUpdate: onUpdate,
          imageService: ImageService(),
        ),
      ),
    ),
  );

  Future<void> tallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  // The labelled plain or Markdown editor field's inner TextField.
  Finder fieldByLabel(String label) => find.descendant(
    of: find.byWidgetPredicate(
      (w) =>
          (w is EditorField && w.label == label) ||
          (w is MarkdownEditorField && w.label == label),
    ),
    matching: find.byType(TextField),
  );

  testWidgets('editing every field round-trips into the emitted spec', (
    tester,
  ) async {
    await tallSurface(tester);
    Slide? updated;
    await tester.pumpWidget(
      host(Slide.create(SlideType.finding), (s) => updated = s),
    );
    await tester.pumpAndSettle();

    await tester.enterText(fieldByLabel('Titel'), 'F-03 · SQL-injectie');
    await tester.enterText(fieldByLabel('Bevinding-id'), 'F-03');
    // Scope object is a bare TextField (with the example-URL hint), not an
    // EditorField.
    await tester.enterText(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == 'https://app.voorbeeld/login',
      ),
      'https://app.example/login',
    );
    await tester.enterText(fieldByLabel('CVSS 4.0-vector'), criticalVector);
    await tester.enterText(
      fieldByLabel('CWE'),
      'CWE-89 — Improper Neutralization of SQL',
    );
    await tester.enterText(fieldByLabel('CVE'), 'CVE-2024-1234, CVE-2024-5678');
    await tester.enterText(
      fieldByLabel('Beschrijving'),
      'De invoer wordt niet gefilterd.',
    );
    await tester.enterText(
      fieldByLabel('Bevestiging (reproductie)'),
      'Payload \' OR 1=1 -- gaf toegang.',
    );
    await tester.enterText(
      fieldByLabel('Mogelijke impact'),
      'Volledige DB-uitlezing.',
    );
    await tester.enterText(
      fieldByLabel('Aanbeveling'),
      'Gebruik parameterized queries.',
    );
    await tester.pump();

    expect(updated, isNotNull);
    final spec = FindingSpec.parse(updated!.customMarkdown);
    expect(updated!.title, 'F-03 · SQL-injectie');
    expect(updated!.findingId, 'F-03');
    expect(spec.heading, 'F-03 · SQL-injectie');
    expect(spec.scopeObject, 'https://app.example/login');
    expect(spec.cvssVector, criticalVector);
    expect(spec.cweId, 89);
    expect(spec.cweName, 'Improper Neutralization of SQL');
    expect(spec.cveIds, ['CVE-2024-1234', 'CVE-2024-5678']);
    expect(spec.description, 'De invoer wordt niet gefilterd.');
    expect(spec.confirmation, contains('OR 1=1'));
    expect(spec.impact, 'Volledige DB-uitlezing.');
    expect(spec.recommendation, 'Gebruik parameterized queries.');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a valid vector shows the derived base score badge', (
    tester,
  ) async {
    await tallSurface(tester);
    await tester.pumpWidget(host(Slide.create(SlideType.finding), (_) {}));
    await tester.pumpAndSettle();

    // No vector yet: no score read-out.
    expect(find.textContaining('Basis'), findsNothing);

    await tester.enterText(fieldByLabel('CVSS 4.0-vector'), criticalVector);
    await tester.pump();

    // The derived base score/severity chip appears (9.3 · Critical).
    expect(find.textContaining('Basis 9.3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unparseable vector shows the "check the vector" hint', (
    tester,
  ) async {
    await tallSurface(tester);
    await tester.pumpWidget(host(Slide.create(SlideType.finding), (_) {}));
    await tester.pumpAndSettle();

    await tester.enterText(fieldByLabel('CVSS 4.0-vector'), 'niet-een-vector');
    await tester.pump();

    expect(find.text('Controleer de CVSS-vector'), findsOneWidget);
    expect(find.textContaining('Basis'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the retest dropdown writes its status and reveals a note field',
    (tester) async {
      await tallSurface(tester);
      Slide? updated;
      await tester.pumpWidget(
        host(Slide.create(SlideType.finding), (s) => updated = s),
      );
      await tester.pumpAndSettle();

      // No outcome yet: no note field.
      expect(find.text('Hertest-notitie'), findsNothing);

      await tester.tap(find.byType(DropdownButtonFormField<RetestStatus>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nog aanwezig').last);
      await tester.pumpAndSettle();

      expect(updated, isNotNull);
      expect(updated!.customMarkdown, contains('**Retest:** NotResolved'));

      // The note field now shows and its text lands in the spec.
      expect(find.text('Hertest-notitie'), findsOneWidget);
      await tester.enterText(
        fieldByLabel('Hertest-notitie'),
        'hertest 2026-07-20, patch toegepast',
      );
      await tester.pump();

      final spec = FindingSpec.parse(updated!.customMarkdown);
      expect(spec.retest, RetestStatus.notResolved);
      expect(spec.retestNote, 'hertest 2026-07-20, patch toegepast');
      expect(tester.takeException(), isNull);
    },
  );
}
