import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/ai_settings.dart';
import 'package:ocideck/services/ai_client_service.dart';
import 'package:ocideck/services/ai_security_gate.dart';
import 'package:ocideck/services/improvement_ai_service.dart';
import 'package:ocideck/state/improvement_ai_provider.dart';
import 'package:ocideck/widgets/editors/improvement_ai_suggest_field.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

class _FakeTransport implements AiHttpTransport {
  _FakeTransport(this.result);
  AiHttpResult result;
  @override
  Future<AiHttpResult> send({
    required String method,
    required Uri url,
    required AiResolveStrategy strategy,
    Map<String, String> headers = const {},
    String? body,
    Duration timeout = const Duration(seconds: 60),
  }) async => result;
}

const _localAi = AiSettings(
  enabled: true,
  mode: AiBackendMode.local,
  baseUrl: 'http://127.0.0.1:11434/v1',
  model: 'gemma3:4b',
);

Widget host({
  required List<Override> overrides,
  required bool hasExistingText,
  required bool isAiDraft,
  VoidCallback? onAccepted,
  ValueChanged<String>? onSuggested,
}) {
  return ProviderScope(
    overrides: [
      improvementAiAvailableProvider.overrideWithValue(true),
      ...overrides,
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('nl'),
      home: Scaffold(
        body: ImprovementAiSuggestField(
          field: ImprovementAiField.canvasRegion,
          fieldKey: 'canvas:goal',
          contextBuilder: () => const ImprovementAiContext(
            slideTitle: 'A3',
            templateId: 'a3',
            fieldLabel: 'Goal',
            existingText: 'bestaand',
            siblingText: 'Background: context',
          ),
          hasExistingText: hasExistingText,
          isAiDraft: isAiDraft,
          onSuggested: onSuggested ?? (_) {},
          onAccepted: onAccepted ?? () {},
        ),
      ),
    ),
  );
}

Override clientFactory(ImprovementAiClientFactory factory) =>
    improvementAiClientFactoryProvider.overrideWithValue(factory);

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('hides when AI unavailable and no draft', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [improvementAiAvailableProvider.overrideWithValue(false)],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('nl'),
          home: Scaffold(
            body: ImprovementAiSuggestField(
              field: ImprovementAiField.canvasRegion,
              fieldKey: 'k',
              contextBuilder: () => const ImprovementAiContext(),
              hasExistingText: false,
              isAiDraft: false,
              onSuggested: (_) {},
              onAccepted: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tekst voorstellen (AI)'), findsNothing);
  });

  testWidgets('shows draft badge and Nagekeken without AI module', (
    tester,
  ) async {
    var accepted = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [improvementAiAvailableProvider.overrideWithValue(false)],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('nl'),
          home: Scaffold(
            body: ImprovementAiSuggestField(
              field: ImprovementAiField.canvasRegion,
              fieldKey: 'k',
              contextBuilder: () => const ImprovementAiContext(),
              hasExistingText: true,
              isAiDraft: true,
              onSuggested: (_) {},
              onAccepted: () => accepted = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nagekeken'));
    await tester.pump();
    expect(accepted, isTrue);
  });

  testWidgets('gate refusal shows settings toast', (tester) async {
    await tester.pumpWidget(
      host(
        overrides: [
          clientFactory(
            () async => throw AiGateException(AiGateDenial.disabled),
          ),
        ],
        hasExistingText: false,
        isAiDraft: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tekst voorstellen (AI)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.textContaining('AI-assistentie is niet beschikbaar'),
      findsOneWidget,
    );
  });

  testWidgets('request failure shows unreachable toast', (tester) async {
    await tester.pumpWidget(
      host(
        overrides: [
          clientFactory(() async => throw AiRequestException('network')),
        ],
        hasExistingText: false,
        isAiDraft: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tekst voorstellen (AI)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('AI-aanroep is mislukt'), findsOneWidget);
  });

  testWidgets('empty draft shows empty-model toast', (tester) async {
    await tester.pumpWidget(
      host(
        overrides: [
          clientFactory(
            () async => AiClientService(
              settings: _localAi,
              hasOutboundConsent: false,
              transport: _FakeTransport(
                const AiHttpResult(
                  200,
                  '{"choices":[{"message":{"content":""}}]}',
                ),
              ),
            ),
          ),
        ],
        hasExistingText: false,
        isAiDraft: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tekst voorstellen (AI)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('geen tekst terug'), findsOneWidget);
  });

  testWidgets('successful draft calls onSuggested after confirm', (
    tester,
  ) async {
    String? got;
    await tester.pumpWidget(
      host(
        overrides: [
          clientFactory(
            () async => AiClientService(
              settings: _localAi,
              hasOutboundConsent: false,
              transport: _FakeTransport(
                const AiHttpResult(
                  200,
                  '{"choices":[{"message":{"content":"Kort doel."}}]}',
                ),
              ),
            ),
          ),
        ],
        hasExistingText: true,
        isAiDraft: true,
        onSuggested: (d) => got = d,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tekst voorstellen (AI)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vervangen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(got, isNotNull);
    expect(got, contains('Kort'));
  });

  testWidgets('generic catch shows unreachable toast', (tester) async {
    await tester.pumpWidget(
      host(
        overrides: [clientFactory(() async => throw StateError('boom'))],
        hasExistingText: false,
        isAiDraft: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tekst voorstellen (AI)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('AI-aanroep is mislukt'), findsOneWidget);
  });

  testWidgets('confirm replace then cancel leaves field alone', (tester) async {
    var suggested = false;
    await tester.pumpWidget(
      host(
        overrides: [
          clientFactory(
            () async => throw AiGateException(AiGateDenial.disabled),
          ),
        ],
        hasExistingText: true,
        isAiDraft: false,
        onSuggested: (_) => suggested = true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tekst voorstellen (AI)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();
    expect(suggested, isFalse);
  });
}
