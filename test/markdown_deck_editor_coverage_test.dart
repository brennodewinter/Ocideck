import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/widgets/editors/markdown_deck_editor.dart';
import 'package:ocideck/widgets/editors/markdown_find_bar.dart';

/// A clean deck that the validator accepts without warnings or errors.
const _validDeck = '# Titel\n\nEen gewone paragraaf zonder problemen.';

/// A deck whose front matter is never closed — a guaranteed validation error.
const _invalidDeck = '---\nmarp: true\n# nooit gesloten\n';

Widget _host({
  required String content,
  bool Function(String)? onApply,
  VoidCallback? onExit,
  bool parseError = false,
}) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 1000,
          height: 1600,
          child: MarkdownDeckEditor(
            initialContent: content,
            onApply: onApply ?? (_) => true,
            parseError: parseError,
            onExitMarkdown: onExit ?? () {},
            onScopeChanged: (_) {},
          ),
        ),
      ),
    ),
  );
}

Future<void> _sendControlKey(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('Toepassen applies clean markdown and leaves markdown mode', (
    tester,
  ) async {
    String? applied;
    var exited = false;
    await tester.pumpWidget(
      _host(
        content: _validDeck,
        onApply: (md) {
          applied = md;
          return true;
        },
        onExit: () => exited = true,
      ),
    );

    await tester.tap(find.text('Toepassen'));
    await tester.pumpAndSettle();

    expect(applied, _validDeck);
    expect(exited, isTrue);
  });

  testWidgets('Controleren on clean markdown reports no problems', (
    tester,
  ) async {
    await tester.pumpWidget(_host(content: _validDeck));

    await tester.tap(find.text('Controleren'));
    await tester.pump();

    expect(find.text('Geen syntaxproblemen gevonden'), findsOneWidget);
  });

  testWidgets('cancel button leaves markdown mode without applying', (
    tester,
  ) async {
    var applied = false;
    var exited = false;
    await tester.pumpWidget(
      _host(
        content: _validDeck,
        onApply: (_) {
          applied = true;
          return true;
        },
        onExit: () => exited = true,
      ),
    );

    await tester.tap(find.text('Annuleren'));
    await tester.pump();

    expect(exited, isTrue);
    expect(applied, isFalse);
  });

  testWidgets('a parse error shows the red banner', (tester) async {
    await tester.pumpWidget(_host(content: _validDeck, parseError: true));

    expect(
      find.textContaining('Markdown kon niet worden verwerkt'),
      findsOneWidget,
    );
  });

  testWidgets('applying invalid markdown and confirming "Toch toepassen"', (
    tester,
  ) async {
    String? applied;
    var exited = false;
    await tester.pumpWidget(
      _host(
        content: _invalidDeck,
        onApply: (md) {
          applied = md;
          return true;
        },
        onExit: () => exited = true,
      ),
    );

    await tester.tap(find.text('Toepassen'));
    await tester.pumpAndSettle();

    // The issues dialog blocks the apply until the author chooses.
    expect(find.text('Syntaxproblemen gevonden'), findsOneWidget);

    await tester.tap(find.text('Toch toepassen'));
    await tester.pumpAndSettle();

    expect(applied, _invalidDeck);
    expect(exited, isTrue);
  });

  testWidgets('applying invalid markdown and choosing "Terug naar editor"', (
    tester,
  ) async {
    var applied = false;
    var exited = false;
    await tester.pumpWidget(
      _host(
        content: _invalidDeck,
        onApply: (_) {
          applied = true;
          return true;
        },
        onExit: () => exited = true,
      ),
    );

    await tester.tap(find.text('Toepassen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terug naar editor'));
    await tester.pumpAndSettle();

    expect(applied, isFalse);
    expect(exited, isFalse);
    // We are back in the editor, not exited.
    expect(find.byType(MarkdownDeckEditor), findsOneWidget);
  });

  testWidgets('tapping an issue in the apply dialog jumps back to the editor', (
    tester,
  ) async {
    var applied = false;
    await tester.pumpWidget(
      _host(
        content: _invalidDeck,
        onApply: (_) {
          applied = true;
          return true;
        },
      ),
    );

    await tester.tap(find.text('Toepassen'));
    await tester.pumpAndSettle();

    // Each issue is a tappable tile ("Regel N: ..."); tapping the one inside the
    // dialog returns to the editor focused on that line without applying.
    // (The validation summary bar behind the dialog also lists issues, so the
    // finder must be scoped to the dialog.)
    await tester.tap(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('Regel '),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(applied, isFalse);
    expect(find.text('Syntaxproblemen gevonden'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('find bar navigates between matches', (tester) async {
    await tester.pumpWidget(_host(content: 'alpha beta alpha gamma alpha'));

    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    await _sendControlKey(tester, LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'alpha');
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);

    await tester.tap(find.byTooltip('Volgende'));
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.tap(find.byTooltip('Vorige'));
    await tester.pump();
    expect(find.text('1 / 3'), findsOneWidget);
  });

  testWidgets('case-sensitive toggle recounts matches', (tester) async {
    await tester.pumpWidget(_host(content: 'Alpha alpha ALPHA'));

    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    await _sendControlKey(tester, LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'alpha');
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);

    // The case-sensitivity toggle is the only checkbox in this editor.
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('1 / 1'), findsOneWidget);
  });

  testWidgets('replace current match swaps only the active occurrence', (
    tester,
  ) async {
    String? applied;
    await tester.pumpWidget(
      _host(
        content: 'foo foo',
        onApply: (md) {
          applied = md;
          return true;
        },
      ),
    );

    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    await _sendControlKey(tester, LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'foo');
    await tester.enterText(fields.at(1), 'bar');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Vervang'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Toepassen'));
    await tester.pumpAndSettle();

    expect(applied, 'bar foo');
  });

  testWidgets('Escape closes the find bar from the editor field', (
    tester,
  ) async {
    await tester.pumpWidget(_host(content: 'alpha beta'));

    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    await _sendControlKey(tester, LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownFindBar), findsOneWidget);

    // Move focus back to the main editor, then Escape via the outer handler.
    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownFindBar), findsNothing);
  });

  testWidgets('find can be opened via the editor provider request', (
    tester,
  ) async {
    await tester.pumpWidget(_host(content: 'alpha beta alpha'));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MarkdownDeckEditor)),
    );
    container
        .read(editorProvider.notifier)
        .requestMarkdownFind(showReplace: true);
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownFindBar), findsOneWidget);
    // Replace row is shown, so its "Vervang alles" action is present.
    expect(find.text('Vervang alles'), findsOneWidget);
  });
}
