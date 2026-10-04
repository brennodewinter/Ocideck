import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/ociserve_intake.dart';
import 'package:ocideck/services/form/form_intake_context.dart';
import 'package:ocideck/services/form/form_intake_snapshot.dart';
import 'package:ocideck/services/ociserve/ociserve_http.dart';
import 'package:ocideck/services/ociserve/ociserve_intake_respondent.dart';
import 'package:ocideck/widgets/forms/form_intake_invitation_dialog.dart';

import 'support/pump_until.dart';
import 'support/temp_dir.dart';

const _form = '''<!-- form id=kook version=1 overview="naam" -->
# Inzending

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->
''';

IntakePublicForm _publicForm({bool accepting = true}) => IntakePublicForm(
  formRef: 'ref-1',
  version: 2,
  accepting: accepting,
  operationalStatus: IntakeOperationalStatus.open,
  snapshot: buildIntakeSnapshot(
    markdown: _form,
    title: 'Aanmelden',
    purposes: const ['deelname'],
    privacyText: 'Kort bewaren.',
    retentionDraftDays: 30,
    retentionSubmittedDays: 365,
    correctionAllowed: false,
  ),
);

class _FakeClient extends IntakeRespondentClient {
  _FakeClient({this.form, this.error})
    : super(baseUrl: 'https://s.example.org');

  IntakePublicForm? form;
  Object? error;

  @override
  Future<IntakePublicForm> publicForm(String formRef) async {
    if (error != null) throw error!;
    return form!;
  }
}

Widget _app({
  required IntakeRespondentClient Function(String) clientFor,
  Future<void> Function(String)? onOpenPath,
  void Function(String)? onOpenText,
  Future<String?> Function(String, String)? pickDestination,
}) => MaterialApp(
  locale: const Locale('nl'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: FormIntakeInvitationDialog(
      clientFor: clientFor,
      onOpenPath: onOpenPath ?? (_) async {},
      onOpenText: onOpenText ?? (_) {},
      pickDestination: pickDestination,
    ),
  ),
);

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('intake_inv');
  });

  tearDown(() => deleteTempDir(dir));

  testWidgets('een link die geen uitnodiging is krijgt een uitleg', (
    tester,
  ) async {
    await tester.pumpWidget(_app(clientFor: (_) => _FakeClient()));
    await tester.enterText(find.byType(TextField), 'dit is geen link');
    await tester.tap(find.text('Link openen'));
    await pumpUntil(
      tester,
      () => find
          .textContaining('geen uitnodigings- of terugkeerlink')
          .evaluate()
          .isNotEmpty,
      reason: 'de foutmelding verscheen niet',
    );
  });

  testWidgets('een http-link wordt niet vervoerd', (tester) async {
    var called = false;
    await tester.pumpWidget(
      _app(
        clientFor: (_) {
          called = true;
          return _FakeClient();
        },
      ),
    );
    await tester.enterText(
      find.byType(TextField),
      'http://s.example.org/forms/ref-1',
    );
    await tester.tap(find.text('Link openen'));
    await tester.pump();
    expect(called, isFalse);
    expect(find.textContaining('https://'), findsWidgets);
  });

  testWidgets('een uitnodiging toont het formulier en vraagt om een plek', (
    tester,
  ) async {
    final path = '${dir.path}/inzending.md';
    String? opened;
    await tester.pumpWidget(
      _app(
        clientFor: (_) => _FakeClient(form: _publicForm()),
        onOpenPath: (p) async => opened = p,
        pickDestination: (title, fileName) async => path,
      ),
    );
    await tester.enterText(
      find.byType(TextField),
      'https://s.example.org/api/v1/intake/forms/ref-1',
    );
    await tester.tap(find.text('Link openen'));
    await pumpUntil(
      tester,
      () => find.text('Formulier invullen').evaluate().isNotEmpty,
      reason: 'de landingsstap kwam nooit',
    );

    expect(find.text('Aanmelden'), findsOneWidget);
    expect(find.textContaining('s.example.org'), findsWidgets);

    await tester.tap(find.text('Formulier invullen'));
    await pumpUntil(
      tester,
      () => opened != null,
      reason: 'het bestand werd niet geopend',
    );

    // Het document is geschreven, de sidecar staat ernaast en de tab opent.
    expect(opened, path);
    expect(File(path).readAsStringSync(), contains('field id=naam'));
    final context = await tester.runAsync(() => readIntakeContext(path));
    expect(context, isNotNull);
    expect(context!.formRef, 'ref-1');
    expect(context.baseUrl, 'https://s.example.org');
  });

  testWidgets('een server die niet bereikbaar is meldt dat, geen crash', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        clientFor: (_) =>
            _FakeClient(error: const OciServeException('unavailable')),
      ),
    );
    await tester.enterText(
      find.byType(TextField),
      'https://s.example.org/forms/ref-1',
    );
    await tester.tap(find.text('Link openen'));
    await pumpUntil(
      tester,
      () => find.textContaining('niet bereikbaar').evaluate().isNotEmpty,
      reason: 'de foutmelding verscheen niet',
    );
    expect(find.text('Link openen'), findsOneWidget);
  });
}
