import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// Alt text for content images (WCAG 1.1.1): a screen reader should read the
/// author's caption when there is one, and otherwise still announce that a
/// picture is present instead of staying silent. Background/decorative images
/// pass `null` and are intentionally not covered here.
void main() {
  tearDown(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('caption becomes the image alt text, trimmed', (tester) async {
    late String label;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            label = imageSemanticsLabel(context, '  Omzet per kwartaal  ');
            return const SizedBox();
          },
        ),
      ),
    );
    expect(label, 'Omzet per kwartaal');
  });

  testWidgets('per-usage alt-text takes precedence over the caption', (
    tester,
  ) async {
    late String label;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            label = imageSemanticsLabel(
              context,
              'Zichtbaar bijschrift',
              altText: '  Beschrijvende alt-tekst  ',
            );
            return const SizedBox();
          },
        ),
      ),
    );
    expect(label, 'Beschrijvende alt-tekst');
  });

  testWidgets('an uncaptioned image still gets a generic alt text', (
    tester,
  ) async {
    late String label;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            label = imageSemanticsLabel(context, '   ');
            return const SizedBox();
          },
        ),
      ),
    );
    expect(label, 'Afbeelding');
  });

  testWidgets('the generic fallback is localised', (tester) async {
    AppLocalizations.setActiveLanguageCode('en');
    late String label;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            label = imageSemanticsLabel(context, '');
            return const SizedBox();
          },
        ),
      ),
    );
    expect(label, 'Image');
  });
}
