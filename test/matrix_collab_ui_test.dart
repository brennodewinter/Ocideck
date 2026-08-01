// The realtime-collaboration UI seam (PR-3c of the #977 slice): the invite/join
// dialogs and the command-palette entries. The session lifecycle itself is
// tested against the fake homeserver in matrix_collab_provider_test.dart; here we
// test only what the user touches — the link dialogs and which commands appear.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_participant.dart';
import 'package:ocideck/collab/matrix_presence.dart';
import 'package:ocideck/state/collaboration_provider.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/matrix_settings.dart';
import 'package:ocideck/state/matrix_client_provider.dart';
import 'package:ocideck/widgets/panels/slide_presence_dots.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/collab_verify_banner.dart';
import 'package:ocideck/widgets/dialogs/matrix_collab_dialogs.dart';

void _noop() {}

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

  group('showMatrixParticipantsDialog', () {
    final keyA = [for (var i = 0; i < 32; i++) i];
    final keyB = [for (var i = 0; i < 32; i++) 255 - i];

    Future<void> openDialog(
      WidgetTester tester, {
      required List<CollabParticipant> Function() participants,
      List<CollabParticipant> Function(CollabParticipant)? onPin,
      List<CollabParticipant> Function(CollabParticipant)? onUnpin,
      void Function(CollabParticipant)? onPinCalled,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showMatrixParticipantsDialog(
                  context,
                  l10nOf(context),
                  participants: participants,
                  onPin: (p) async => onPinCalled?.call(p),
                  onUnpin: (p) async {},
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    testWidgets('lists each device with its fingerprint, self first', (
      tester,
    ) async {
      final participants = [
        CollabParticipant(
          userId: '@me:hs',
          deviceId: 'DEV1',
          identityKey: keyA,
          fingerprint: 'AAAA BBBB',
          isSelf: true,
          trust: TrustState.verified,
        ),
        CollabParticipant(
          userId: '@peer:hs',
          deviceId: 'DEV2',
          identityKey: keyB,
          fingerprint: 'CCCC DDDD',
          isSelf: false,
        ),
      ];
      await openDialog(tester, participants: () => participants);
      expect(find.text('AAAA BBBB'), findsOneWidget);
      expect(find.text('CCCC DDDD'), findsOneWidget);
      expect(find.textContaining('@me:hs'), findsOneWidget);
      expect(find.textContaining('(dit apparaat)'), findsOneWidget);
      expect(find.text('@peer:hs'), findsOneWidget);
      // An unverified peer offers a "mark verified" action; self does not.
      expect(find.text('Markeer als geverifieerd'), findsOneWidget);
    });

    testWidgets('a mismatch shows the warning, not a plain verify button', (
      tester,
    ) async {
      final participants = [
        CollabParticipant(
          userId: '@peer:hs',
          deviceId: 'DEV2',
          identityKey: keyB,
          fingerprint: 'CCCC DDDD',
          isSelf: false,
          trust: TrustState.mismatch,
        ),
      ];
      await openDialog(tester, participants: () => participants);
      expect(find.text('Wijkt af'), findsOneWidget);
      expect(
        find.textContaining('mogelijk zit er iemand tussen'),
        findsOneWidget,
      );
      expect(find.text('Markeer als geverifieerd'), findsNothing);
    });

    testWidgets('marking a peer verified re-reads and updates the row', (
      tester,
    ) async {
      // A mutable list the pin callback flips, mirroring the trust store.
      var trust = TrustState.unverified;
      List<CollabParticipant> current() => [
        CollabParticipant(
          userId: '@peer:hs',
          deviceId: 'DEV2',
          identityKey: keyB,
          fingerprint: 'CCCC DDDD',
          isSelf: false,
          trust: trust,
        ),
      ];
      await openDialog(
        tester,
        participants: current,
        onPinCalled: (_) => trust = TrustState.verified,
      );
      expect(find.text('Markeer als geverifieerd'), findsOneWidget);
      await tester.tap(find.text('Markeer als geverifieerd'));
      await tester.pumpAndSettle();
      expect(find.text('Geverifieerd'), findsOneWidget);
      expect(find.text('Markeer als geverifieerd'), findsNothing);
    });
  });

  group('CollabVerifyBannerView', () {
    testWidgets('renders nothing when not visible', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CollabVerifyBannerView(visible: false, onVerify: _noop),
          ),
        ),
      );
      expect(find.text('Verifiëren'), findsNothing);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('shows the prompt and fires onVerify on tap', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CollabVerifyBannerView(
              visible: true,
              onVerify: () => tapped++,
            ),
          ),
        ),
      );
      expect(find.textContaining('Nog niet elk apparaat'), findsOneWidget);
      await tester.tap(find.text('Verifiëren'));
      expect(tapped, 1);
    });
  });

  group('SlidePresenceDots', () {
    PeerPresence peer(String user, String device) =>
        PeerPresence(userId: user, deviceId: device, slideId: 's1');

    testWidgets('shows a dot per peer with an initial', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlidePresenceDots([
              peer('@alice:hs', 'D1'),
              peer('@bob:hs', 'D2'),
            ]),
          ),
        ),
      );
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('caps the row and shows a +N overflow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlidePresenceDots([
              for (var i = 0; i < 5; i++) peer('@u$i:hs', 'D$i'),
            ], maxShown: 3),
          ),
        ),
      );
      // 2 shown + a "+3" overflow chip = 3 markers total.
      expect(find.text('+3'), findsOneWidget);
    });

    testWidgets('renders nothing when empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SlidePresenceDots([]))),
      );
      expect(find.byType(Tooltip), findsNothing);
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

    testWidgets(
      'offers Matrix host/join when the module is on and an account is set',
      (tester) async {
        final labels = await labelsWith(tester, [
          matrixCollabActiveProvider.overrideWithValue(true),
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
      },
    );

    testWidgets('offers no Matrix commands without an account', (tester) async {
      final labels = await labelsWith(tester, [
        matrixCollabActiveProvider.overrideWithValue(true),
        matrixAccountProvider.overrideWithValue(null),
      ]);
      expect(labels, isNot(contains('Realtime samenwerken starten')));
      expect(labels, isNot(contains('Deelnemen via een link')));
    });

    testWidgets('offers no Matrix commands when the module is off', (
      tester,
    ) async {
      // Account configured, but the module (or its Matrix toggle) is off.
      final labels = await labelsWith(tester, [
        matrixCollabActiveProvider.overrideWithValue(false),
        matrixAccountProvider.overrideWithValue(
          const MatrixServer(
            homeserverUrl: 'https://hs.example',
            userId: '@u:hs.example',
            deviceId: 'DEV1',
          ),
        ),
      ]);
      expect(labels, isNot(contains('Realtime samenwerken starten')));
      expect(labels, isNot(contains('Deelnemen via een link')));
    });
  });
}
