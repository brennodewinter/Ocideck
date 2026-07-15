import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/export_readiness.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/privacy_badge.dart';

// De exportstatusbalk hoort bij een privacymelding hetzelfde PrivacyKat-merk te
// tonen als de slide-badge en het kwaliteitspaneel — niet het generieke
// waarschuwingsicoon. Dit bewaakt zowel de merkkeuze (wélke statussen) als het
// merk zelf (dat het de PrivacyKat-SVG rendert).
void main() {
  test('alleen de privacystatussen dragen het PrivacyKat-merk', () {
    expect(
      statusShowsPrivacyMark(ExportReadinessStatus.privacyWarnings),
      isTrue,
    );
    expect(
      statusShowsPrivacyMark(ExportReadinessStatus.blockedByPrivacy),
      isTrue,
    );
    for (final other in [
      ExportReadinessStatus.ready,
      ExportReadinessStatus.qualityWarnings,
      ExportReadinessStatus.needsSave,
      ExportReadinessStatus.blockedByClassification,
      ExportReadinessStatus.blockedByQuality,
    ]) {
      expect(statusShowsPrivacyMark(other), isFalse, reason: other.name);
    }
  });

  testWidgets('PrivacyKatMark rendert de PrivacyKat-SVG', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: PrivacyKatMark())),
      ),
    );
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
