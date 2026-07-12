import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/markdown_safety.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/dialogs/import_security_alarm_dialog.dart';

/// Behaviour tests for the "unsafe presentation blocked" alarm: it is a hard
/// stop that lists every rejected finding verbatim (threat label · line +
/// evidence) and only lets the user acknowledge.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  const l10n = AppLocalizations(Locale('nl'));

  test('threatLabel maps every threat kind to a Dutch label', () {
    expect(
      ImportSecurityAlarmDialog.threatLabel(
        l10n,
        MarkdownThreat.scriptExecution,
      ),
      'Scriptuitvoering',
    );
    expect(
      ImportSecurityAlarmDialog.threatLabel(
        l10n,
        MarkdownThreat.embeddedContent,
      ),
      'Ingesloten inhoud',
    );
    expect(
      ImportSecurityAlarmDialog.threatLabel(l10n, MarkdownThreat.unsafeUrl),
      'Onveilige URL',
    );
  });

  testWidgets('the alarm lists each finding and can only be acknowledged', (
    tester,
  ) async {
    const alarm = ImportSecurityAlarm(
      path: '/tmp/evil.md',
      findings: [
        MarkdownSafetyFinding(
          kind: MarkdownThreat.scriptExecution,
          line: 3,
          evidence: '<script>alert(1)</script>',
        ),
        MarkdownSafetyFinding(
          kind: MarkdownThreat.embeddedContent,
          line: 9,
          evidence: '<iframe src=...>',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ImportSecurityAlarmDialog.show(context, alarm),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Onveilige presentatie geblokkeerd'), findsOneWidget);
    expect(find.text('Scriptuitvoering · Regel 3'), findsOneWidget);
    expect(find.text('Ingesloten inhoud · Regel 9'), findsOneWidget);
    // Each finding shows its offending fragment verbatim.
    expect(find.byType(SelectableText), findsNWidgets(2));

    // The single action acknowledges and closes; there is no "open anyway".
    expect(find.byType(FilledButton), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('Onveilige presentatie geblokkeerd'), findsNothing);
  });
}
