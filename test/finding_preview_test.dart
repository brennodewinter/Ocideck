import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/cvss_builder.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

const _headerBody =
    '# F-03 · SQL injection in the login form\n'
    '\n'
    '**Scope object:** `https://app.client.example/login`\n'
    '**CVSS 4.0:** 9.3 (Critical) · '
    '`CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N`\n'
    '**CWE:** [CWE-89 — Improper Neutralization of SQL]'
    '(https://cwe.mitre.org/data/definitions/89.html)\n'
    '**CVE:** [CVE-2024-1234](https://nvd.nist.gov/vuln/detail/CVE-2024-1234)\n'
    '\n'
    '## Description\n\nx\n';

Widget _host(Slide slide, {Map<String, CiaRating> scopeCia = const {}}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 800,
          height: 450,
          child: SlidePreviewWidget(
            slide: slide,
            themeProfile: const ThemeProfile(),
            scopeCia: scopeCia,
          ),
        ),
      ),
    ),
  );
}

Slide _finding(String body) => Slide.create(
  SlideType.finding,
).copyWith(customMarkdown: body, findingId: 'F-03');

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('finding renders a derived CVSS badge and CWE/CVE chips', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_finding(_headerBody)));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // Score + severity band are derived from the vector, not read from text.
    expect(find.text('9.3 · Critical'), findsOneWidget);
    expect(find.text('CWE-89'), findsOneWidget);
    expect(find.text('CVE-2024-1234'), findsOneWidget);
    expect(
      find.textContaining('SQL injection in the login form'),
      findsOneWidget,
    );
  });

  testWidgets('a rated scope object adds a context badge beside the base', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _finding(_headerBody),
        scopeCia: const {
          'https://app.client.example/login': CiaRating(
            confidentiality: CiaLevel.low,
            integrity: CiaLevel.low,
            availability: CiaLevel.low,
          ),
        },
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    // Base score is still shown (labelled), plus a CIA-weighted context score.
    expect(find.textContaining('Basis 9.3'), findsOneWidget);
    expect(find.textContaining('Context'), findsOneWidget);
  });

  testWidgets('a finding with no CVSS renders without a badge or a crash', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_finding('# F-01 · Bare finding\n\n## Description\n\nx\n')),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Bare finding'), findsOneWidget);
    // No CVSS vector → no severity badge text of the form "score · band".
    expect(find.textContaining(' · Critical'), findsNothing);
  });
}
