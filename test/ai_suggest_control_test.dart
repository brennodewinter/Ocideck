import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/editors/ai_suggest_control.dart';

Widget _host({
  required Future<String> Function() loadSuggestion,
  bool isAvailable = true,
  bool hasExistingText = false,
  bool isAiDraft = false,
  ValueChanged<String>? onSuggested,
  VoidCallback? onAccepted,
}) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('nl'),
  home: Scaffold(
    body: AiSuggestControl(
      isAvailable: isAvailable,
      hasExistingText: hasExistingText,
      isAiDraft: isAiDraft,
      loadSuggestion: loadSuggestion,
      onSuggested: onSuggested ?? (_) {},
      onAccepted: onAccepted ?? () {},
    ),
  ),
);

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('toont voortgang en blokkeert een tweede aanvraag', (
    tester,
  ) async {
    final response = Completer<String>();
    var calls = 0;
    String? suggested;
    await tester.pumpWidget(
      _host(
        loadSuggestion: () {
          calls += 1;
          return response.future;
        },
        onSuggested: (draft) => suggested = draft,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tekst voorstellen (AI)'));
    await tester.pump();

    expect(find.text('Bezig met AI-analyse…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(calls, 1);

    await tester.tap(find.text('Bezig met AI-analyse…'));
    expect(calls, 1);

    response.complete('Gedeeld concept');
    await tester.pumpAndSettle();
    expect(suggested, 'Gedeeld concept');
    expect(find.text('Tekst voorstellen (AI)'), findsOneWidget);
  });

  testWidgets('annuleren bij bestaande tekst start geen aanvraag', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _host(
        hasExistingText: true,
        loadSuggestion: () async {
          calls += 1;
          return 'concept';
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tekst voorstellen (AI)'));
    await tester.pumpAndSettle();
    expect(
      find.text('Er staat al tekst. Vervangen door het AI-concept?'),
      findsOneWidget,
    );

    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('conceptmarkering blijft bruikbaar zonder AI-backend', (
    tester,
  ) async {
    var accepted = false;
    await tester.pumpWidget(
      _host(
        isAvailable: false,
        isAiDraft: true,
        loadSuggestion: () async => 'ongebruikt',
        onAccepted: () => accepted = true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tekst voorstellen (AI)'), findsNothing);
    expect(find.text('AI-concept'), findsOneWidget);
    await tester.tap(find.text('Nagekeken'));
    await tester.pump();
    expect(accepted, isTrue);
  });
}
