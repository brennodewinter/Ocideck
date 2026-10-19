// Toetst dat de band het documentlogo op zíjn papieraandeel tekent (#2462).
// De PDF deelt dezelfde maat (`documentLogoWidthPt`) en dezelfde begrenzing;
// wat hier op het scherm staat, is wat de export op het vel zet.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/page_size.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/widgets/document_page_chrome.dart';
import 'package:ocideck/widgets/theme_profile_logo.dart';

void main() {
  Future<void> pumpBand(
    WidgetTester tester, {
    required ThemeProfile profile,
    double bandWidth = 452,
    double? contentWidthPt,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: bandWidth,
            child: DocumentChromeBand(
              profile: profile,
              header: true,
              compact: true,
              contentWidthPt: contentWidthPt ?? kDefaultDocumentContentWidthPt,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  double logoWidth(WidgetTester tester) =>
      tester.getSize(find.byType(ThemeProfileLogo)).width;

  testWidgets('het logo vult zijn papieraandeel in de voorvertoning', (
    tester,
  ) async {
    // Standaard: 96 px → 72 pt op papier. Een band van 452 px staat voor de
    // standaardspiegel van ~481,9 pt, dus 72 pt ≈ 67,5 px op het scherm.
    const profile = ThemeProfile(documentLogoPath: 'merk.png');
    await pumpBand(tester, profile: profile);
    expect(
      logoWidth(tester),
      closeTo(452 * 72 / kDefaultDocumentContentWidthPt, 0.5),
    );
  });

  testWidgets('een grotere instelling geeft een groter bandlogo', (
    tester,
  ) async {
    // 240 px → 180 pt; op dezelfde 452 px band ≈ 169 px.
    const profile = ThemeProfile(
      documentLogoPath: 'merk.png',
      documentLogoSize: 240,
    );
    await pumpBand(tester, profile: profile);
    expect(
      logoWidth(tester),
      closeTo(452 * 180 / kDefaultDocumentContentWidthPt, 0.5),
    );
  });

  testWidgets('de bovengrens is zichtbaar: het logo eet de koptekst niet', (
    tester,
  ) async {
    // 480 px → 360 pt — meer dan het vaste spiegelaandeel; de band kapt
    // zichtbaar af in plaats van de koptekst weg te drukken.
    const profile = ThemeProfile(
      documentLogoPath: 'merk.png',
      documentLogoSize: 480,
    );
    await pumpBand(tester, profile: profile);
    expect(logoWidth(tester), closeTo(452 * kDocumentBandLogoWidthShare, 0.5));
  });
}
