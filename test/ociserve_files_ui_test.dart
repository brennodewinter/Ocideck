import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ociserve_file_contract/ociserve_file_contract.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/ociserve_models.dart';
import 'package:ocideck/models/ociserve_settings.dart';
import 'package:ocideck/services/ociserve/ociserve_gateway.dart';
import 'package:ocideck/services/ociserve/ociserve_http.dart';
import 'package:ocideck/state/ociserve_provider.dart';
import 'package:ocideck/widgets/dialogs/ociserve_file_browser.dart';
import 'package:ocideck/widgets/dialogs/ociserve_file_shares.dart';
import 'package:ocideck/widgets/dialogs/ociserve_passkeys_button.dart';

const file = CatalogEntry(
  id: '12345678-1234-4234-8234-123456789abc',
  name: 'Veilig.md',
  directory: false,
  size: 3,
  etag: '"v1"',
);
const folder = CatalogEntry(
  id: '12345678-1234-4234-8234-123456789abd',
  name: 'Lesmateriaal',
  directory: true,
);
const root = CatalogEntry(id: 'root', name: '', directory: true);
const memberships = [
  OciServeMembership(
    organizationId: 'org-a',
    name: 'Team A',
    capabilities: ['content:create', 'content:edit'],
  ),
  OciServeMembership(
    organizationId: 'org-b',
    name: 'Team B',
    capabilities: ['content:create'],
  ),
];
const initial = OciServeState(
  settings: OciServeSettings(enabled: true, baseUrl: 'https://files.example'),
  status: OciServeStatus.authenticated,
  account: OciServeAccount(id: 'a', memberships: memberships),
);

class Api implements OciServeApi {
  final folders = <String>[];
  String? cursor;
  Completer<CatalogPage>? delay;
  bool revoked = false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<CatalogPage> files({
    required String accessToken,
    required String organizationId,
    String folderId = 'root',
    String? cursor,
  }) async {
    folders.add('$organizationId:$folderId');
    this.cursor = cursor;
    if (delay != null && organizationId == 'org-a') {
      return delay!.future;
    }
    if (organizationId == 'org-b') {
      return const CatalogPage(root, [], [CatalogCrumb('root', '')], null);
    }
    return CatalogPage(
      folderId == 'root' ? root : folder,
      folderId == 'root' ? [folder] : [file],
      [
        const CatalogCrumb('root', ''),
        if (folderId != 'root') CatalogCrumb(folder.id, folder.name),
      ],
      folderId == 'root'
          ? null
          : cursor == null
          ? 'page2'
          : null,
    );
  }

  @override
  Future<Uint8List> fileContent({
    required String accessToken,
    required String organizationId,
    required CatalogEntry entry,
  }) async => Uint8List.fromList([35, 32, 65]);
  @override
  Future<ManagedSharePage> fileShares({
    required String accessToken,
    required String organizationId,
    String? cursor,
  }) async => ManagedSharePage([
    ManagedFileShare(
      id: file.id,
      rootId: folder.id,
      expiresAt: DateTime.utc(2099),
      status: 'active',
      passwordProtected: true,
      revision: 2,
    ),
  ], null);
  @override
  Future<void> revokeFileShare({
    required String accessToken,
    required String organizationId,
    required String shareId,
  }) async {
    revoked = true;
  }
}

class Session extends OciServeNotifier {
  Session(this.api);
  final Api api;
  OciServeState starting = initial;
  int passkeyCalls = 0;
  @override
  Future<bool> managePasskeys() async {
    passkeyCalls++;
    return true;
  }

  @override
  OciServeState build() => starting;
  @override
  Future<T> fileOperation<T>(
    String organizationId,
    Future<T> Function(OciServeApi, String) operation, {
    OciServeRequestScope? scope,
  }) => operation(api, 'not-a-real-token');
  void signOut() =>
      state = const OciServeState(status: OciServeStatus.signedOut);
}

Future<ProviderContainer> host(
  WidgetTester tester,
  Api api,
  Widget dialog, {
  void Function(OciServeFileSelection?)? onSelection,
}) async {
  AppLocalizations.setActiveLanguageCode('nl');
  final container = ProviderContainer(
    overrides: [ociServeProvider.overrideWith(() => Session(api))],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
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
              onPressed: () => showDialog<OciServeFileSelection>(
                context: context,
                builder: (_) => dialog,
              ).then((value) => onSelection?.call(value)),
              child: const Text('Start'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Start'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'account passkey action is capability driven and explicitly opens the provider',
    (tester) async {
      final session = Session(Api())
        ..starting = initial.copyWith(
          account: OciServeAccount(
            id: 'a',
            memberships: memberships,
            passwordlessEnrollable: true,
            passkeyManagementUrl: Uri.parse('https://id.example/account'),
          ),
        );
      final container = ProviderContainer(
        overrides: [ociServeProvider.overrideWith(() => session)],
      );
      addTearDown(container.dispose);
      AppLocalizations.setActiveLanguageCode('nl');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('nl'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: OciServePasskeysButton()),
          ),
        ),
      );
      expect(session.passkeyCalls, 0);
      await tester.tap(find.text('Passkeys beheren'));
      await tester.pumpAndSettle();
      expect(session.passkeyCalls, 1);
      session.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Passkeys beheren'), findsNothing);
    },
  );

  testWidgets(
    'catalog navigates breadcrumbs, paginates and returns a credential-free copy',
    (tester) async {
      final api = Api();
      OciServeFileSelection? selection;
      await host(
        tester,
        api,
        const OciServeFileBrowser(),
        onSelection: (value) => selection = value,
      );
      expect(find.text('Team A'), findsOneWidget);
      await tester.tap(find.text('Lesmateriaal'));
      await tester.pumpAndSettle();
      expect(find.text('Veilig.md'), findsOneWidget);
      await tester.tap(find.text('Volgende pagina'));
      await tester.pumpAndSettle();
      expect(api.cursor, 'page2');
      await tester.tap(find.text('Hoofdmap'));
      await tester.pumpAndSettle();
      expect(api.folders.last, 'org-a:root');
      expect(find.text('Veilig.md'), findsNothing);
      await tester.tap(find.text('Lesmateriaal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Veilig.md'));
      await tester.pumpAndSettle();
      expect(selection?.origin.fileId, file.id);
      expect(selection?.origin.etag, file.etag);
      expect(selection?.origin.organizationId, 'org-a');
      expect(selection?.bytes, [35, 32, 65]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'switching organization rejects a late listing and clears tenant metadata',
    (tester) async {
      final api = Api()..delay = Completer<CatalogPage>();
      // The listing deliberately remains pending; do not settle an animated progress bar.
      AppLocalizations.setActiveLanguageCode('nl');
      final container = ProviderContainer(
        overrides: [ociServeProvider.overrideWith(() => Session(api))],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('nl'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: OciServeFileBrowser()),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Team B').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      api.delay!.complete(
        const CatalogPage(root, [file], [CatalogCrumb('root', '')], null),
      );
      await tester.pumpAndSettle();
      expect(find.text('Veilig.md'), findsNothing);
      expect(find.text('Deze map is leeg.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('logout clears a browser listing and management metadata', (
    tester,
  ) async {
    final api = Api();
    final container = await host(tester, api, const OciServeFileBrowser());
    expect(find.text('Lesmateriaal'), findsOneWidget);
    (container.read(ociServeProvider.notifier) as Session).signOut();
    await tester.pumpAndSettle();
    expect(find.text('Lesmateriaal'), findsNothing);
    expect(
      find.text('De sessie is gewijzigd. Open de bron opnieuw.'),
      findsOneWidget,
    );
  });
  testWidgets(
    'revocation requires confirmation and does not copy anything implicitly',
    (tester) async {
      var clipboardCalls = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') clipboardCalls++;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final api = Api();
      await host(
        tester,
        api,
        const OciServeFileShares(organizationId: 'org-a'),
      );
      expect(find.textContaining('Met wachtwoord'), findsOneWidget);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Intrekken'));
      await tester.pumpAndSettle();
      expect(api.revoked, false);
      await tester.tap(find.text('Bevestigen'));
      await tester.pumpAndSettle();
      expect(api.revoked, true);
      expect(clipboardCalls, 0);
    },
  );
}
