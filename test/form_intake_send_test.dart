import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/ociserve_intake.dart';
import 'package:ocideck/services/form/form_intake_context.dart';
import 'package:ocideck/services/form/form_intake_snapshot.dart';
import 'package:ocideck/services/ociserve/ociserve_http.dart';
import 'package:ocideck/services/ociserve/ociserve_intake_respondent.dart';
import 'package:ocideck/widgets/forms/form_intake_send_dialog.dart';

import 'support/pump_until.dart';

const _form = '''<!-- form id=kook version=1 overview="naam" -->
# Inzending

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->
''';

const _context = FormIntakeContext(
  baseUrl: 'https://s.example.org',
  formRef: 'ref-1',
);

IntakePublicForm _publicForm() => IntakePublicForm(
  formRef: 'ref-1',
  version: 2,
  accepting: true,
  operationalStatus: IntakeOperationalStatus.open,
  snapshot: buildIntakeSnapshot(
    markdown: _form,
    title: 'Aanmelden',
    purposes: const ['deelname'],
    privacyText: 'Kort bewaren.',
    retentionDraftDays: 30,
    retentionSubmittedDays: 365,
    correctionAllowed: true,
  ),
);

/// De respondenttransport gesimuleerd: de stappen lopen zoals de server ze
/// beschrijft, zodat de reis zelf — en wat hij teruggeeft — getoetst wordt.
class _FakeClient extends IntakeRespondentClient {
  _FakeClient({this.failSubmit = false})
    : super(baseUrl: 'https://s.example.org');

  final bool failSubmit;

  List<int>? drafted;
  var submitted = false;

  static const _grant = IntakeGrant(
    token: 'tok',
    expiresIn: Duration(minutes: 5),
    purpose: IntakePurpose.start,
    locator: 'loc-1',
    formRef: 'ref-1',
  );

  @override
  Future<IntakePublicForm> publicForm(String formRef) async => _publicForm();

  @override
  Future<IntakeChallenge> requestChallenge({
    required IntakePurpose purpose,
    required String email,
    String? formRef,
    String? locator,
  }) async => const IntakeChallenge(
    challengeId: 'ch-1',
    expiresIn: Duration(minutes: 10),
    resendAfter: Duration(seconds: 30),
  );

  @override
  Future<IntakeGrant> verifyChallenge({
    required String challengeId,
    required String code,
  }) async => _grant;

  @override
  Future<OciServeEtag<IntakeRespondentSubmission>?> submission({
    required IntakeGrant grant,
    String? ifNoneMatch,
  }) async => OciServeEtag(
    IntakeRespondentSubmission(
      locator: grant.locator,
      state: IntakeSubmissionState.draft,
      revision: 0,
      draftPresent: false,
      allowedActions: const [IntakeAllowedAction.submit],
    ),
    'e1',
  );

  @override
  Future<IntakeDraftReceipt> putDraft({
    required IntakeGrant grant,
    required List<int> bytes,
  }) async {
    drafted = bytes;
    return IntakeDraftReceipt(sha256: 'x' * 64, size: bytes.length);
  }

  @override
  Future<IntakeSubmitReceipt> submit({
    required IntakeGrant grant,
    required String idempotencyKey,
    required String expectedSha256,
    required int expectedSize,
  }) async {
    if (failSubmit) throw const OciServeException('unavailable');
    submitted = true;
    return IntakeSubmitReceipt(
      revision: 1,
      submittedAt: DateTime.utc(2026, 10, 5),
      sha256: 'x' * 64,
      size: expectedSize,
    );
  }
}

Widget _app({
  required _FakeClient client,
  required void Function(FormIntakeContext?) onDone,
}) => MaterialApp(
  locale: const Locale('nl'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () async => onDone(
          await showFormIntakeSendDialog(
            context,
            intakeContext: _context,
            package: const [1, 2, 3],
            clientFor: (_) => client,
          ),
        ),
        child: const Text('open'),
      ),
    ),
  ),
);

/// Rijdt de dialoog: open → bestemming → Insturen → e-mail → code →
/// bevestigen → done. Geeft terug hoe ver hij kwam.
Future<void> _driveToConfirm(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await pumpUntil(
    tester,
    () => find.text('Insturen…').evaluate().isNotEmpty,
    reason: 'de bestemmingsstap kwam nooit',
  );
  await tester.tap(find.text('Insturen…'));
  await tester.pump();
  await tester.enterText(
    find.widgetWithText(TextField, 'Je e-mailadres'),
    'sari@example.org',
  );
  await tester.tap(find.text('Code aanvragen'));
  await pumpUntil(
    tester,
    () => find
        .widgetWithText(TextField, 'Code uit de e-mail')
        .evaluate()
        .isNotEmpty,
    reason: 'het codeveld kwam nooit',
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Code uit de e-mail'),
    '123456',
  );
  await tester.tap(find.text('Code controleren'));
  await pumpUntil(
    tester,
    () => find.text('Definitief insturen').evaluate().isNotEmpty,
    reason: 'de bevestigingsstap kwam nooit',
  );
}

void main() {
  testWidgets(
    'de volledige verzendreis legt de revisie vast en meldt de context',
    (tester) async {
      final client = _FakeClient();
      FormIntakeContext? result;
      var closed = false;
      await tester.pumpWidget(
        _app(
          client: client,
          onDone: (r) {
            result = r;
            closed = true;
          },
        ),
      );

      await _driveToConfirm(tester);
      expect(find.textContaining('revisie 1'), findsOneWidget);

      await tester.tap(find.text('Definitief insturen'));
      await pumpUntil(
        tester,
        () => find
            .textContaining('Verstuurd als revisie 1')
            .evaluate()
            .isNotEmpty,
        reason: 'de inzending werd niet vastgelegd',
      );
      expect(client.drafted, [1, 2, 3]);
      expect(client.submitted, isTrue);

      await tester.tap(find.text('Sluiten'));
      await tester.pump();
      expect(closed, isTrue);
      expect(result!.locator, 'loc-1');
      expect(result!.revision, 1);
      expect(result!.lastState, IntakeSubmissionState.submitted);
    },
  );

  testWidgets('een mislukt versturen legt niets vast en het werk blijft', (
    tester,
  ) async {
    final client = _FakeClient(failSubmit: true);
    await tester.pumpWidget(_app(client: client, onDone: (_) {}));

    await _driveToConfirm(tester);
    await tester.tap(find.text('Definitief insturen'));
    await pumpUntil(
      tester,
      () => find.textContaining('niet bereikbaar').evaluate().isNotEmpty,
      reason: 'de foutmelding verscheen niet',
    );
    expect(find.textContaining('je werk staat veilig'), findsWidgets);
    expect(client.drafted, [1, 2, 3]);
    expect(client.submitted, isFalse);
  });
}
