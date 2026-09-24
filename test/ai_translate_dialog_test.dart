import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/services/ai_client_service.dart';
import 'package:ocideck/services/ai_security_gate.dart';
import 'package:ocideck/services/ai_translate_service.dart';
import 'package:ocideck/widgets/dialogs/ai_translate_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget child) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('nl'),
    home: Scaffold(body: child),
  ),
);

DeckTranslationResult _result() => DeckTranslationResult(
  deck: Deck(title: 'Vertaald', language: 'en', slides: const []),
  translatedSlides: 1,
  failedSlides: 0,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocalizations.setActiveLanguageCode('nl');
  });

  testWidgets('vertalen roept de callback aan en sluit met het resultaat', (
    tester,
  ) async {
    DeckTranslationResult? popped;
    String? usedCode;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              popped = await showAiTranslateDialog(
                ctx,
                initialLanguageCode: 'en',
                translate: (code, name, onProgress, isCancelled) async {
                  usedCode = code;
                  onProgress(1, 2);
                  onProgress(2, 2);
                  return _result();
                },
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Vertaal met AI'), findsOneWidget);
    await tester.tap(find.text('Vertalen'));
    await tester.pumpAndSettle();

    expect(usedCode, 'en');
    expect(popped, isNotNull);
    expect(find.text('Vertaal met AI'), findsNothing);
  });

  testWidgets('een mislukte aanroep toont de fout en blijft open', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showAiTranslateDialog(
              ctx,
              initialLanguageCode: 'en',
              translate: (_, _, _, _) async =>
                  throw AiRequestException('network'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vertalen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('mislukt'), findsOneWidget);
    // Terug in de keuzestand: Vertalen is weer beschikbaar.
    expect(find.text('Vertalen'), findsOneWidget);
  });

  testWidgets('een gate-weigering toont de beschikbaarheidsmelding', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showAiTranslateDialog(
              ctx,
              initialLanguageCode: 'en',
              translate: (_, _, _, _) async =>
                  throw AiGateException(AiGateDenial.cloudNeedsConsent),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vertalen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('niet beschikbaar'), findsOneWidget);
    expect(find.text('Vertalen'), findsOneWidget);
  });

  testWidgets('annuleren tijdens de run keert terug naar de keuzestap', (
    tester,
  ) async {
    final gate = Completer<void>();
    bool Function()? cancelProbe;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showAiTranslateDialog(
              ctx,
              initialLanguageCode: 'en',
              translate: (code, name, onProgress, isCancelled) async {
                onProgress(0, 3);
                cancelProbe = isCancelled;
                await gate.future;
                return null;
              },
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vertalen'));
    await tester.pump();

    // Voortgang zichtbaar, Vertalen-knop weg tijdens de run.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Vertalen'), findsNothing);

    await tester.tap(find.text('Annuleren'));
    await tester.pump();
    expect(cancelProbe!(), isTrue);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Vertalen'), findsOneWidget);
  });
}
