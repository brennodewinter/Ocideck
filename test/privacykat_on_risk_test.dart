import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/state/deck_quality_provider.dart';
import 'package:ocideck/state/image_contrast_provider.dart';
import 'package:ocideck/state/privacy_provider.dart';
import 'package:ocideck/widgets/panels/slide_quality_panel.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// Het PrivacyKat-merkteken hoort te verschijnen wáár een privacyrisico wordt
/// aangewezen — niet alleen als egress-markering in de statusbalk.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('de shield-badge op de slide toont de PrivacyKat', (
    tester,
  ) async {
    // Een slide met de "waarschuw de ontvanger"-dispositie krijgt de badge die
    // op elk renderoppervlak meekomt.
    final shielded = Slide.create(
      SlideType.title,
    ).copyWith(title: 'Zaak 2026-114', privacy: PrivacyDisposition.shield);
    final plain = Slide.create(
      SlideType.title,
    ).copyWith(title: 'Zaak 2026-114');

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              height: 450,
              child: SlidePreviewWidget(
                slide: shielded,
                themeProfile: const ThemeProfile(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PERSOONSGEGEVENS'), findsOneWidget);
    expect(find.byType(SvgPicture), findsWidgets);
    expect(tester.takeException(), isNull);

    // Zonder de dispositie geen badge — dus ook geen SVG-merk.
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              height: 450,
              child: SlidePreviewWidget(
                slide: plain,
                themeProfile: const ThemeProfile(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('PERSOONSGEGEVENS'), findsNothing);
  });

  testWidgets('een privacyrij in het kwaliteitspaneel toont de PrivacyKat', (
    tester,
  ) async {
    // Eén privacybevinding, via de gewone bridge-categorie. De rij hoort het
    // merkteken te dragen in plaats van het generieke waarschuwingsicoon.
    const privacyIssue = SlideQualityIssue(
      slideIndex: 0,
      kind: SlideQualityIssueKind.privacyIdentifier,
      category: SlideQualityCategory.privacy,
      severity: MarkdownValidationSeverity.warning,
      args: {'rule': 'nl.bsn', 'sample': '1…9'},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Het paneel voegt sync-kwaliteit, beeldcontrast en privacy samen;
          // hier leveren we alleen de privacybevinding en houden de rest leeg.
          deckQualityProvider.overrideWithValue(const SlideQualityResult([])),
          imageContrastIssuesProvider.overrideWith(
            (ref) => Future.value(const <SlideQualityIssue>[]),
          ),
          privacyQualityIssuesProvider.overrideWithValue(const [privacyIssue]),
        ],
        child: const MaterialApp(
          localizationsDelegates: [AppLocalizations.delegate],
          home: Scaffold(body: SlideQualityPanel(embedded: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // De bevinding staat er (via haar gemaskeerde fragment) én het merk erbij.
    expect(find.byType(SvgPicture), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
