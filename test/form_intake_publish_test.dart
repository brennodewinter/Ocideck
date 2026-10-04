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
import 'package:ocideck/widgets/forms/form_intake_publish_dialog.dart';

import 'support/pump_until.dart';
import 'support/temp_dir.dart';

const _form = '''<!-- form id=kook version=1 overview="naam" -->
# Inzending

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->
''';

const _account = OciServeAccount(
  id: 'u1',
  memberships: [OciServeMembership(organizationId: 'org-1', name: 'Redactie')],
);

const _authenticated = OciServeState(
  settings: OciServeSettings(enabled: true, baseUrl: 'https://s.example.org'),
  status: OciServeStatus.authenticated,
  account: _account,
);

/// De intake-kant van de gateway gesimuleerd: de aanmaak en de volgende
/// versie komen terug zoals OciServe ze beschrijft.
class _FakeIntakeApi implements OciServeIntakeApi {
  var created = 0;
  var republished = 0;

  static final _published = DateTime.utc(2026, 10, 5);
  static final _form = IntakeForm(
    formId: 'srv-form-1',
    formRef: 'pub-ref-1',
    name: 'kook v1',
    operationalStatus: IntakeOperationalStatus.open,
    activeVersion: 1,
    versions: const [],
    createdAt: _published,
  );

  @override
  Future<IntakeForm> createIntakeForm({
    required String accessToken,
    required String organizationId,
    required String name,
    required IntakeFormSnapshot snapshot,
    required String idempotencyKey,
  }) async {
    created++;
    return _form;
  }

  @override
  Future<IntakeFormVersion> publishIntakeFormVersion({
    required String accessToken,
    required String organizationId,
    required String formId,
    required IntakeFormSnapshot snapshot,
    required String idempotencyKey,
  }) async {
    republished++;
    return IntakeFormVersion(
      version: 2,
      sha256: 'x' * 64,
      publishedAt: DateTime.utc(2026, 10, 5),
      snapshot: snapshot,
    );
  }

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _PublishNotifier extends OciServeNotifier {
  _PublishNotifier(this.api);

  final _FakeIntakeApi api;

  @override
  OciServeState build() => _authenticated;

  @override
  Future<T> withIntakeGateway<T>(
    String organizationId,
    Future<T> Function(OciServeIntakeApi api, String accessToken) call,
  ) => call(api, 'token');
}

Widget _app({
  required _PublishNotifier notifier,
  required FormWorkspace workspace,
  required List<PublishedForm> forms,
  required void Function(bool?) onDone,
}) => ProviderScope(
  overrides: [ociServeProvider.overrideWith(() => notifier)],
  child: MaterialApp(
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
            await showFormIntakePublishDialog(
              context,
              workspace: workspace,
              forms: forms,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

Future<void> _fill(WidgetTester tester) async {
  await tester.tap(find.text('Organisatie'));
  await tester.pump();
  await tester.tap(find.text('Redactie').last);
  await tester.pump();
  await tester.enterText(
    find.widgetWithText(TextField, 'Titel die de invuller ziet'),
    'Aanmelden',
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Doelen (één per regel)'),
    'deelname',
  );
  await tester.pump();
}

void main() {
  late Directory dir;
  late FormWorkspace workspace;
  late List<PublishedForm> forms;

  /// De publicatiedialoog is hoger dan het standaard testoppervlak; de
  /// knoppen onderaan moeten binnen beeld liggen om aan te kunnen tikken.
  Future<void> pumpApp(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(child);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('intake_pub');
    workspace = FormWorkspace(dir.path);
    await workspace.publishForm(_form);
    forms = (await workspace.publishedForms()).forms;
  });

  tearDown(() => deleteTempDir(dir));

  testWidgets('een eerste publicatie legt record en uitnodigingslink vast', (
    tester,
  ) async {
    final api = _FakeIntakeApi();
    bool? result;
    await pumpApp(
      tester,
      _app(
        notifier: _PublishNotifier(api),
        workspace: workspace,
        forms: forms,
        onDone: (r) => result = r,
      ),
    );
    await tester.tap(find.text('open'));
    await pumpUntil(
      tester,
      () => find.text('kook · v1').evaluate().isNotEmpty,
      reason: 'het formulier werd niet gekozen',
    );

    await _fill(tester);
    await tester.ensureVisible(find.text('Publiceren'));
    await tester.pump();
    await tester.tap(find.text('Publiceren'));
    await pumpUntil(
      tester,
      () => find
          .textContaining('gepubliceerd als versie 1')
          .evaluate()
          .isNotEmpty,
      reason: 'de publicatie kwam nooit terug',
    );
    expect(api.created, 1);
    expect(
      find.textContaining(
        'https://s.example.org/api/v1/intake/forms/pub-ref-1',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Sluiten'));
    await tester.pump();
    expect(result, isTrue);

    final record = await tester.runAsync(
      () => readIntakeRecord(workspace, forms.first.id),
    );
    expect(record, isNotNull);
    expect(record!.formRef, 'pub-ref-1');
    expect(record.activeVersion, 1);
  });

  testWidgets(
    'een volgende publicatie wordt versie n+1, nooit een overschrijving',
    (tester) async {
      await tester.runAsync(
        () => writeIntakeRecord(
          workspace,
          forms.first.id,
          const IntakeOrganiserRecord(
            baseUrl: 'https://s.example.org',
            organizationId: 'org-1',
            formId: 'srv-form-1',
            formRef: 'pub-ref-1',
            activeVersion: 1,
          ),
        ),
      );
      final api = _FakeIntakeApi();
      await pumpApp(
        tester,
        _app(
          notifier: _PublishNotifier(api),
          workspace: workspace,
          forms: forms,
          onDone: (_) {},
        ),
      );
      await tester.tap(find.text('open'));
      await pumpUntil(
        tester,
        () => find.text('Als nieuwe versie publiceren').evaluate().isNotEmpty,
        reason: 'het record werd niet gelezen',
      );

      await _fill(tester);
      await tester.ensureVisible(find.text('Als nieuwe versie publiceren'));
      await tester.pump();
      await tester.tap(find.text('Als nieuwe versie publiceren'));
      await pumpUntil(
        tester,
        () => find.textContaining('versie 2').evaluate().isNotEmpty,
        reason: 'de nieuwe versie kwam nooit terug',
      );
      expect(api.republished, 1);
      expect(api.created, 0);

      final record = await tester.runAsync(
        () => readIntakeRecord(workspace, forms.first.id),
      );
      expect(record!.activeVersion, 2);
    },
  );
}
