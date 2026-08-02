import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/control_status_spec.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// Render tests for the `controlStatus` slide preview (ISO_MANAGEMENTSYSTEEM
/// §4): it reads the typed [ControlStatusSpec] view over the slide's title and
/// table rows and draws the section heading, a derived implemented/applicable
/// progress bar, and one row per control with a localised status chip. The
/// tally is derived from the rows, so these tests pin that the rendered
/// percentage follows the data and that a fully out-of-scope section reports 0%
/// instead of dividing by zero.
Slide _controlStatusSlide(String heading, List<ControlStatusRow> rows) =>
    Slide.create(SlideType.controlStatus).copyWith(
      title: heading,
      tableRows: ControlStatusSpec(heading: heading, rows: rows).toTableRows(),
    );

// Rendered in a real interface font (Roboto), not the flutter-test square
// font, so the progress Row's proportional text measures as it does in the app
// instead of overflowing on a test-only glyph width.
Widget _host(Slide slide) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 800,
        height: 450,
        child: SlidePreviewWidget(
          slide: slide,
          themeProfile: const ThemeProfile(fontFamily: 'Roboto'),
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bytes = File('assets/fonts/Roboto-Variable.ttf').readAsBytesSync();
    await (FontLoader('Roboto')..addFont(
          Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
        ))
        .load();
  });

  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('renders the heading, controls and derived progress', (
    tester,
  ) async {
    final slide = _controlStatusSlide('ISO 27001 · Annex A (A.5)', const [
      ControlStatusRow(
        id: 'A.5.1',
        control: 'Beleid voor informatiebeveiliging',
        status: ControlStatus.implemented,
        maturity: 4,
      ),
      ControlStatusRow(
        id: 'A.5.2',
        control: 'Rollen en verantwoordelijkheden',
        status: ControlStatus.partial,
      ),
      ControlStatusRow(
        id: 'A.5.3',
        control: 'Functiescheiding',
        status: ControlStatus.notStarted,
      ),
      ControlStatusRow(
        id: 'A.5.4',
        control: 'Uitzondering',
        status: ControlStatus.notApplicable,
      ),
    ]);

    await tester.pumpWidget(_host(slide));
    await tester.pump();

    // Heading, the localised column header, and every control id/title show.
    expect(find.text('ISO 27001 · Annex A (A.5)'), findsOneWidget);
    expect(find.text('Beheersmaatregel'), findsOneWidget);
    expect(find.text('A.5.1'), findsOneWidget);
    expect(find.text('Beleid voor informatiebeveiliging'), findsOneWidget);
    expect(find.text('Functiescheiding'), findsOneWidget);

    // Derived tally: 1 implemented of 3 applicable (the not-applicable row is
    // out of the denominator) → 33%.
    expect(find.textContaining('33%'), findsOneWidget);

    // The localised status chips render, plus the maturity fraction.
    expect(find.text('Deels'), findsOneWidget);
    expect(find.text('Niet van toepassing'), findsOneWidget);
    expect(find.text('4/5'), findsOneWidget);
  });

  testWidgets('a fully not-applicable section reports 0% without dividing '
      'by zero', (tester) async {
    final slide = _controlStatusSlide('Buiten scope', const [
      ControlStatusRow(
        id: 'A.9.1',
        control: 'Toegangsbeleid',
        status: ControlStatus.notApplicable,
      ),
    ]);

    await tester.pumpWidget(_host(slide));
    await tester.pump();

    expect(find.text('Buiten scope'), findsOneWidget);
    expect(find.textContaining('0%'), findsOneWidget);
  });
}
