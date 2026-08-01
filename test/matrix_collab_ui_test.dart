// The realtime-collaboration UI seam (PR-3c of the #977 slice): the invite/join
// dialogs and the command-palette entries. The session lifecycle itself is
// tested against the fake homeserver in matrix_collab_provider_test.dart; here we
// test only what the user touches — the link dialogs and which commands appear.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/matrix_settings.dart';
import 'package:ocideck/state/matrix_client_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/dialogs/matrix_collab_dialogs.dart';

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  AppLocalizations l10nOf(BuildContext context) => AppLocalizations.of(context);

  group('promptMatrixInvite', () {
    testWidgets('returns the trimmed link on submit', (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async =>
                    result = await promptMatrixInvite(context, l10nOf(context)),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        '  https://matrix.to/#/x  ',
      );
      await tester.tap(find.text('Deelnemen'));
      await tester.pumpAndSettle();
      expect(result, 'https://matrix.to/#/x');
    });

    testWidgets('returns null on cancel', (tester) async {
      String? result = 'unset';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async =>
                    result = await promptMatrixInvite(context, l10nOf(context)),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'x');
      await tester.tap(find.text('Annuleren'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });

  group('showMatrixInviteDialog', () {
    testWidgets('shows the link and copies it', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showMatrixInviteDialog(
                  context,
                  l10nOf(context),
                  'https://matrix.to/#/!room:hs',
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('https://matrix.to/#/!room:hs'), findsOneWidget);

      await tester.tap(find.text('Kopiëren'));
      await tester.pumpAndSettle();
      expect(copied, ['https://matrix.to/#/!room:hs']);
      expect(find.text('Uitnodigingslink gekopieerd.'), findsOneWidget);
    });
  });

  group('collabPaletteCommands (Matrix)', () {
    Future<List<String>> labelsWith(
      WidgetTester tester,
      List<Override> overrides,
    ) async {
      late List<String> labels;
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  labels = collabPaletteCommands(
                    context,
                    ref,
                    l10nOf(context),
                  ).map((c) => c.label).toList();
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      return labels;
    }

    testWidgets('offers Matrix host/join when an account is configured', (
      tester,
    ) async {
      final labels = await labelsWith(tester, [
        matrixAccountProvider.overrideWithValue(
          const MatrixServer(
            homeserverUrl: 'https://hs.example',
            userId: '@u:hs.example',
            deviceId: 'DEV1',
          ),
        ),
      ]);
      expect(labels, contains('Realtime samenwerken starten'));
      expect(labels, contains('Deelnemen via een link'));
    });

    testWidgets('offers no Matrix commands without an account', (tester) async {
      final labels = await labelsWith(tester, [
        matrixAccountProvider.overrideWithValue(null),
      ]);
      expect(labels, isNot(contains('Realtime samenwerken starten')));
      expect(labels, isNot(contains('Deelnemen via een link')));
    });
  });
}
