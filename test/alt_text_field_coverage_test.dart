import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/ai_settings.dart';
import 'package:ocideck/widgets/editors/alt_text_field.dart';

/// Behaviour coverage for [AltTextField], the reusable WCAG alt-text input:
/// keystrokes reach [AltTextField.onChanged]; an external value resync does
/// not; the AI-draft badge exposes a "reviewed" action; and — when the optional
/// AI backend is configured — a "suggest" button appears and fails gracefully
/// when the image cannot be read.
Widget _host(Widget child) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      FlutterQuillLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SizedBox(width: 1200, height: 1800, child: child)),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocalizations.setActiveLanguageCode('nl');
  });

  testWidgets('keystrokes reach onChanged', (tester) async {
    final seen = <String>[];
    await tester.pumpWidget(
      _host(
        AltTextField(
          altText: '',
          imagePath: 'images/x.png',
          captionBasePath: null,
          onChanged: seen.add,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Een grafiek');
    await tester.pump();

    expect(seen.last, 'Een grafiek');
  });

  testWidgets('an external value change resyncs without firing onChanged', (
    tester,
  ) async {
    var changes = 0;
    Widget build(String alt) => _host(
      AltTextField(
        altText: alt,
        imagePath: 'images/x.png',
        captionBasePath: null,
        onChanged: (_) => changes++,
      ),
    );

    await tester.pumpWidget(build('Eerste'));
    expect(find.text('Eerste'), findsOneWidget);

    // Re-pump the same widget position with a new value: didUpdateWidget must
    // resync the controller with its listener detached, so no spurious edit.
    await tester.pumpWidget(build('Tweede'));
    await tester.pump();

    expect(find.text('Tweede'), findsOneWidget);
    expect(changes, 0);
  });

  testWidgets('an AI-draft shows the badge and a reviewed action', (
    tester,
  ) async {
    var accepted = 0;
    await tester.pumpWidget(
      _host(
        AltTextField(
          altText: 'AI-concept tekst',
          imagePath: 'images/x.png',
          captionBasePath: null,
          onChanged: (_) {},
          isAiDraft: true,
          onAccepted: () => accepted++,
        ),
      ),
    );

    expect(find.text('AI-concept'), findsOneWidget);

    await tester.tap(find.text('Nagekeken'));
    await tester.pump();

    expect(accepted, 1);
  });

  testWidgets(
    'the AI-suggest button appears when configured and fails gracefully on a '
    'missing image',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'aiSettings': jsonEncode(
          const AiSettings(
            enabled: true,
            mode: AiBackendMode.local,
            baseUrl: 'http://127.0.0.1:11434/v1',
            model: 'gemma3:4b',
          ).toJson(),
        ),
      });

      var suggested = 0;
      await tester.pumpWidget(
        _host(
          AltTextField(
            altText: '',
            imagePath: 'images/missing.png',
            captionBasePath: null,
            onChanged: (_) {},
            onSuggested: (_) => suggested++,
          ),
        ),
      );
      // Let settingsProvider load the AI config from the mock store.
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text('Stel alt-tekst voor (AI)'), findsOneWidget);

      await tester.tap(find.text('Stel alt-tekst voor (AI)'));
      await tester.pumpAndSettle();

      // A non-existent image yields null bytes → a toast, no suggestion, and
      // no unhandled exception.
      expect(
        find.text('Kon de afbeelding niet lezen voor AI-analyse.'),
        findsOneWidget,
      );
      expect(suggested, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
