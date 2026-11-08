import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/platform/deep_link_cleanup.dart';
import 'package:ocideck/platform/markdown_transfer.dart';
import 'package:ocideck/services/markdown_transfer_bridge.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/markdown_transfer_flow.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// De gebruikerskant van de postMessage-browserkoppeling (#2827): de
/// toestemmingsvraag toont de origin, Weigeren stuurt `declined` terug en
/// Openen stuurt de tekst door dezelfde poort als geplakte Markdown en
/// rapporteert `opened` — nooit inhoud.
void main() {
  late Directory tmp;

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    tmp = Directory.systemTemp.createTempSync('ocideck_transfer_flow');
    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      'storageConnections': jsonEncode([]),
    });
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  final replies = <Map<String, Object?>>[];
  final requests = <InboundMarkdownRequest>[];
  late MarkdownTransferBridge bridge;

  InboundMarkdownRequest offer() {
    bridge.handleMessage(
      {'type': 'ocideck:init', 'version': 1},
      'https://intake.example',
      true,
      replies.add,
    );
    bridge.handleMessage(
      {
        'type': 'ocideck:open-markdown',
        'version': 1,
        'id': 'r1',
        'name': 'a.md',
        'markdown': '# getuige\n\nlopende tekst',
      },
      'https://intake.example',
      true,
      replies.add,
    );
    return requests.last;
  }

  /// Het element van de AppShell is zowel BuildContext als WidgetRef —
  /// ConsumerStatefulElement vervult beide rollen.
  ({BuildContext context, WidgetRef ref}) shell(WidgetTester tester) {
    final el = tester.element(find.byType(AppShell));
    return (context: el, ref: el as WidgetRef);
  }

  Future<void> pumpApp(WidgetTester tester) async {
    replies.clear();
    requests.clear();
    bridge = MarkdownTransferBridge(
      trustedOrigins: const [],
      onRequest: requests.add,
    );
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
  }

  testWidgets('de toestemmingsvraag toont de origin; weigeren = declined', (
    tester,
  ) async {
    await pumpApp(tester);
    final s = shell(tester);
    unawaited(answerMarkdownTransfer(s.context, s.ref, offer(), bridge));
    await tester.pumpAndSettle();
    expect(find.textContaining('intake.example'), findsOneWidget);
    expect(find.textContaining('a.md'), findsOneWidget);
    await tester.tap(find.text('Weigeren'));
    await tester.pumpAndSettle();
    expect(replies.last['status'], 'declined');
    expect(replies.last.containsKey('markdown'), isFalse);
  });

  testWidgets('openen stuurt de tekst door de openpoort; site hoort opened', (
    tester,
  ) async {
    await pumpApp(tester);
    final s = shell(tester);
    unawaited(answerMarkdownTransfer(s.context, s.ref, offer(), bridge));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Openen'));
    await tester.pumpAndSettle();
    expect(replies.last['status'], 'opened');
    expect(replies.last.containsKey('markdown'), isFalse);
  });

  test('platform-noops draaien buiten de browser zonder effect', () {
    // De io-helften en de conditional-import-naadjes: op desktop is er
    // geen adresbalk en geen postMessage — aanroepen mag geen fout zijn.
    replaceAddressBar(Uri.parse('https://ocideck.example/?deck=x'));
    startMarkdownListener((data, origin, isParent, reply) {});
  });
}
