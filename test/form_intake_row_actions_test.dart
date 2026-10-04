import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/ociserve_intake.dart';
import 'package:ocideck/models/ociserve_models.dart';
import 'package:ocideck/models/ociserve_settings.dart';
import 'package:ocideck/services/form/form_intake_organiser.dart';
import 'package:ocideck/services/form/form_workspace.dart';
import 'package:ocideck/services/ociserve/ociserve_gateway.dart';
import 'package:ocideck/state/ociserve_provider.dart';
import 'package:ocideck/widgets/forms/form_intake_row_actions.dart';

import 'support/pump_until.dart';
import 'support/temp_dir.dart';

const _form = '''<!-- form id=kook version=1 overview="naam" -->
# Inzending

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->
''';

/// De lokale inzending die de link naar de serverinzending legt.
const _sid = 'aaaaaaaaaaaaaaaaaaaaaaaaaa';

const _account = OciServeAccount(
  id: 'u1',
  memberships: [OciServeMembership(organizationId: 'org-1', name: 'Redactie')],
);

const _authenticated = OciServeState(
  settings: OciServeSettings(enabled: true, baseUrl: 'https://s.example.org'),
  status: OciServeStatus.authenticated,
  account: _account,
);

class _FakeIntakeApi implements OciServeIntakeApi {
  var handledCalls = 0;
  bool? lastHandled;
  String? correctionReason;
  var purgeCalls = 0;

  IntakeSubmissionDetail _detail({
    IntakeSubmissionState state = IntakeSubmissionState.submitted,
    bool handled = true,
  }) => IntakeSubmissionDetail(
    submissionId: 'srv-sub-1',
    state: state,
    revision: 1,
    handled: handled,
    createdAt: DateTime.utc(2026, 10, 5),
    revisions: const [],
  );

  @override
  Future<IntakeSubmissionDetail> markIntakeHandled({
    required String accessToken,
    required String organizationId,
    required String formId,
    required String submissionId,
    required bool handled,
    required String idempotencyKey,
  }) async {
    handledCalls++;
    lastHandled = handled;
    return _detail(handled: handled);
  }

  @override
  Future<IntakeSubmissionDetail> openIntakeCorrection({
    required String accessToken,
    required String organizationId,
    required String formId,
    required String submissionId,
    DateTime? deadlineAt,
    String? reason,
    required String idempotencyKey,
  }) async {
    correctionReason = reason;
    return _detail(state: IntakeSubmissionState.correctionOpen);
  }

  @override
  Future<void> purgeIntakeSubmission({
    required String accessToken,
    required String organizationId,
    required String formId,
    required String submissionId,
    required String idempotencyKey,
  }) async {
    purgeCalls++;
  }

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Doet alsof de intake-gateway bereikbaar is; de echte mixin wordt hier
/// bewust omzeild — test 4 roept hem juist wél aan.
class _RowNotifier extends OciServeNotifier {
  _RowNotifier(this.api);

  final _FakeIntakeApi api;

  @override
  OciServeState build() => _authenticated;

  @override
  Future<T> withIntakeGateway<T>(
    String organizationId,
    Future<T> Function(OciServeIntakeApi api, String accessToken) call,
  ) => call(api, 'token');
}

/// Geen overschrijving: `withIntakeGateway` loopt de echte mixin door, die
/// zonder sessietokens bij `_accessToken` strandt — het lidmaatschap komt er
/// wél doorheen.
class _NoSessionNotifier extends OciServeNotifier {
  @override
  OciServeState build() => _authenticated;
}

void main() {
  late Directory dir;
  late FormWorkspace workspace;
  late String localFormId;

  String? doneMessage;

  Future<void> pumpApp(WidgetTester tester, OciServeNotifier notifier) async {
    doneMessage = null;
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [ociServeProvider.overrideWith(() => notifier)],
        child: MaterialApp(
          locale: const Locale('nl'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: FormIntakeRowActions(
              workspace: workspace,
              sid: _sid,
              onDone: (message) => doneMessage = message,
            ),
          ),
        ),
      ),
    );
    await pumpUntil(
      tester,
      () => find.textContaining('Via OciServe').evaluate().isNotEmpty,
      reason: 'de inzendingslink werd niet gevonden',
    );
  }

  /// Zet een record met één servergekoppelde inzending klaar.
  Future<void> seedLink({bool handled = false}) => writeIntakeRecord(
    workspace,
    localFormId,
    IntakeOrganiserRecord(
      baseUrl: 'https://s.example.org',
      organizationId: 'org-1',
      formId: 'srv-form-1',
      formRef: 'pub-ref-1',
      activeVersion: 1,
      submissions: {
        'srv-sub-1': IntakeSubmissionLink(
          sid: _sid,
          revision: 1,
          state: IntakeSubmissionState.submitted,
          handled: handled,
        ),
      },
    ),
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('intake_row');
    workspace = FormWorkspace(dir.path);
    await workspace.publishForm(_form);
    localFormId = (await workspace.publishedForms()).forms.first.id;
  });

  tearDown(() => deleteTempDir(dir));

  testWidgets('als behandeld markeren werkt het lokale record bij', (
    tester,
  ) async {
    await tester.runAsync(seedLink);
    final api = _FakeIntakeApi();
    await pumpApp(tester, _RowNotifier(api));

    await tester.tap(find.text('Als behandeld markeren'));
    await pumpUntil(
      tester,
      () => doneMessage != null,
      reason: 'de serveractie kwam nooit terug',
    );
    expect(api.handledCalls, 1);
    expect(api.lastHandled, isTrue);
    expect(doneMessage, 'Als behandeld gemarkeerd op de server.');

    final record = await tester.runAsync(
      () => readIntakeRecord(workspace, localFormId),
    );
    expect(record!.submissions['srv-sub-1']!.handled, isTrue);
  });

  testWidgets('een correctieronde vraagt een reden en meldt de server', (
    tester,
  ) async {
    await tester.runAsync(seedLink);
    final api = _FakeIntakeApi();
    await pumpApp(tester, _RowNotifier(api));

    await tester.tap(find.text('Correctieronde openen…'));
    await pumpUntil(
      tester,
      () => find.text('Waarom (niet verplicht)').evaluate().isNotEmpty,
      reason: 'het bevestigingsvenster kwam niet op',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Waarom (niet verplicht)'),
      'naam klopt niet',
    );
    await tester.tap(
      find.widgetWithText(FilledButton, 'Correctieronde openen'),
    );
    await pumpUntil(
      tester,
      () => doneMessage != null,
      reason: 'de correctie kwam nooit terug',
    );
    expect(api.correctionReason, 'naam klopt niet');
    expect(doneMessage, 'Correctieronde geopend op de server.');
  });

  testWidgets('opschonen vraagt bevestiging en haalt de link weg', (
    tester,
  ) async {
    await tester.runAsync(seedLink);
    final api = _FakeIntakeApi();
    await pumpApp(tester, _RowNotifier(api));

    await tester.tap(find.text('Opschonen op de server…'));
    await pumpUntil(
      tester,
      () => find.text('Opschonen op de server').evaluate().isNotEmpty,
      reason: 'het bevestigingsvenster kwam niet op',
    );
    await tester.tap(find.text('Opschonen op de server'));
    await pumpUntil(
      tester,
      () => doneMessage != null,
      reason: 'de opschoning kwam nooit terug',
    );
    expect(api.purgeCalls, 1);
    expect(doneMessage, 'Opschonen ingepland op de server.');

    final record = await tester.runAsync(
      () => readIntakeRecord(workspace, localFormId),
    );
    expect(record!.submissions, isNot(contains('srv-sub-1')));
  });

  testWidgets('zonder sessie verandert er niets', (tester) async {
    await tester.runAsync(seedLink);
    await pumpApp(tester, _NoSessionNotifier());

    await tester.tap(find.text('Als behandeld markeren'));
    await pumpUntil(
      tester,
      () => find
          .text('Dat lukte niet op de server. Er is niets veranderd.')
          .evaluate()
          .isNotEmpty,
      reason: 'de fout meldde zich niet',
    );

    final record = await tester.runAsync(
      () => readIntakeRecord(workspace, localFormId),
    );
    expect(record!.submissions['srv-sub-1']!.handled, isFalse);
    expect(doneMessage, isNull);
  });
}
