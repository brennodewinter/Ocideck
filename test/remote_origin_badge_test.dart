import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/privacy_badge.dart';

/// The remote-origin privacy badge's pure bits: the tooltip composition and the
/// bundled PrivacyKat mark. The badge itself is exercised through the status bar.
void main() {
  const l10n = AppLocalizations(Locale('nl'));
  final base = l10n.d(
    'Van een externe URL opgehaald; het openen heeft die server benaderd.',
  );

  test('tooltip is the translated explanation plus the source host', () {
    final tip = remoteOriginTooltip('https://decks.example.org/q4.md', l10n);
    expect(tip, startsWith(base));
    expect(tip, endsWith('(decks.example.org)'));
  });

  test('tooltip omits the host suffix when the URL has none', () {
    expect(remoteOriginTooltip('not a url', l10n), base);
  });

  test('PrivacyKat mark is a well-formed SVG in the EU palette', () {
    expect(privacyKatSvg, startsWith('<svg'));
    expect(privacyKatSvg, contains('</svg>'));
    expect(privacyKatSvg, contains('#003399')); // EU blue
    expect(privacyKatSvg, contains('#FFCC00')); // EU yellow
  });

  testWidgets('PrivacyKat mark renders through flutter_svg', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SvgPicture.string(privacyKatSvg, width: 16, height: 16),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('PrivacyBadge', () {
    Future<void> pump(WidgetTester tester, {String? label}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: PrivacyBadge(
                  tooltip: 'Dit verlaat je apparaat',
                  label: label,
                ),
              ),
            ),
          ),
        );

    testWidgets('shows the mark and the caption when given one', (
      tester,
    ) async {
      await pump(tester, label: 'Extern');
      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.text('Extern'), findsOneWidget);
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        'Dit verlaat je apparaat',
      );
    });

    // De CVE-schakelaar heeft al een eigen titel: daar is alleen het merkje met
    // de uitleg gewenst, geen tweede label ernaast.
    testWidgets('renders mark-only when no caption is given', (tester) async {
      await pump(tester);
      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byType(Text), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
