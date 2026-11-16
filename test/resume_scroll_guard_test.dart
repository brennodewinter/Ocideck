import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor.dart';
import 'package:ocideck/widgets/markdown_editor/resume_scroll_guard.dart';

/// #2914: Cmd+Tab weg-en-terug parkeert `FocusManager` de primaire focus en
/// zet hem op `resumed` terug op dezelfde node. Quill beantwoordt die
/// terugkeer met `_showCaretOnScreen` — een `animateTo` naar de caret, ook
/// als de gebruiker bewust weg had gescrold (bij een caret op een embed:
/// naar de mermaid-kaart). De guard slikt die ene onterechte scroll.
void main() {
  const theme = MarkdownEditorTheme(
    surface: Colors.white,
    text: Colors.black,
    hint: Colors.grey,
    link: Colors.blue,
    heading: Colors.black,
    subheading: Colors.black54,
    codeBackground: Color(0xFFF1F5F9),
    toolbarIcon: Colors.black,
    accent: Colors.blue,
    border: Colors.grey,
  );

  /// De focus-pauzeer/herstel van `FocusManager` staat alleen aan op
  /// desktopplatformen; in tests is het doelplatform anders dan macOS.
  /// De override moet vóór het einde van de test weer weg — de
  /// invariant-check draait vóór de tearDowns.
  void simulateDesktop() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    FocusManager.instance.listenToApplicationLifecycleChangesIfSupported();
  }

  testWidgets('slikt de eerste animateTo na hervatting, laat de rest door', (
    tester,
  ) async {
    simulateDesktop();
    final focus = FocusNode();
    final guard = ResumeScrollGuard(focusNode: focus);
    addTearDown(() {
      focus.dispose();
      guard.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          focusNode: focus,
          child: ListView(
            controller: guard,
            children: [for (var i = 0; i < 200; i++) Text('regel $i')],
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    guard.jumpTo(300);
    expect(guard.offset, 300);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    // De eerste animateTo ná de hervatting is Quills onterechte reveal.
    unawaited(
      guard.animateTo(
        0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(guard.offset, 300, reason: 'de reveal wordt geslikt');

    // Daarna is de vlag weg: eigen scrolls werken weer.
    unawaited(
      guard.animateTo(
        0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(guard.offset, 0);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('zonder geparkeerde focus blijft animateTo gewoon werken', (
    tester,
  ) async {
    simulateDesktop();
    final focus = FocusNode();
    final guard = ResumeScrollGuard(focusNode: focus);
    addTearDown(() {
      focus.dispose();
      guard.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          focusNode: focus,
          child: ListView(
            controller: guard,
            children: [for (var i = 0; i < 200; i++) Text('regel $i')],
          ),
        ),
      ),
    );
    await tester.pump();
    guard.jumpTo(300);

    // Geen focus → geen opschorting → geen bewapening.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    unawaited(
      guard.animateTo(
        0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(guard.offset, 0);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('app-hervatting rolt een weggescrolde caret niet in beeld', (
    tester,
  ) async {
    simulateDesktop();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final controller = TextEditingController(
      text: [
        '# Eerste kop',
        '',
        for (var i = 0; i < 60; i++) 'Regel $i met lopende tekst eromheen.',
        '',
        '```mermaid\ngraph TD\n  A --> B\n```',
        '',
        for (var i = 60; i < 120; i++) 'Nog regel $i met tekst.',
      ].join('\n'),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownNotesEditor(
            controller: controller,
            focusNode: focus,
            editorTheme: theme,
            hintText: '',
            expand: true,
            showToolbar: false,
            showModeToggle: false,
            mode: NotesEditorMode.visual,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(QuillEditor),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    focus.requestFocus();
    await tester.pump();
    // De focus-verkrijging zelf lokt ook een caret-reveal uit; laat die
    // eerst uitspelen zodat de test straks alleen de hervattingsreveal meet.
    await tester.pump(const Duration(milliseconds: 200));
    // Binnen de scrollruimte blijven: een offset voorbij het maximum wordt
    // door de dimensie-correctie teruggezet, en die annuleert elke lopende
    // animatie — dan meet de test niets meer.
    scrollable.position.jumpTo(1000);
    await tester.pump();
    final before = scrollable.position.pixels;
    expect(before, 1000);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    // Laat Quills reveal en zijn animatie aflopen.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    // De reveal vuurde daadwerkelijk — en werd geslikt. Zo is bewezen dat de
    // ketting (opschorting → focus-terugkeer → reveal → slik) echt liep en de
    // test niet alleen passeert omdat er niets gebeurde.
    final guard = scrollable.widget.controller! as ResumeScrollGuard;
    expect(
      guard.swallowedForTesting,
      1,
      reason: 'de hervattingsreveal moest precies één keer geslikt worden',
    );
    // Geen reveal: hooguit een clamp op een gewijzigde maximale scrollruimte
    // (de caret- en selectielaag verdwijnen bij focusverlies), nooit een
    // sprong naar de caret zoals hierboven gemeten (~8 px).
    expect(
      scrollable.position.pixels,
      math.min(before, scrollable.position.maxScrollExtent),
      reason: 'hervatten mag niet naar de caret springen',
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
