import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/rich_text_layout.dart';
import 'package:ocideck/services/slide_layout_metrics.dart';

/// De instelbare lettergrootte voor kop- en voettekst (#3164).
///
/// Voorheen tekende elke dia de Marp-kop en de voet op `w × 0,0145` — op een
/// 1280-brede dia is dat 18,56 pt. De instelling bewaart die maat als
/// standaard, dus een profiel dat niets instelt mag er geen pixel anders uit
/// komen te zien.
void main() {
  group('standaard en schaal', () {
    test('de standaard is exact de oude vaste maat', () {
      expect(kSlideChromeFontSizeDefault, closeTo(1280 * 0.0145, 0.0001));

      const profile = ThemeProfile();
      const w = kReferenceSlideWidth;
      expect(profile.slideHeaderFontSizeAt(w), closeTo(w * 0.0145, 0.001));
      expect(profile.slideFooterFontSizeAt(w), closeTo(w * 0.0145, 0.001));
    });

    test('de maat schaalt mee met de diabreedte', () {
      const profile = ThemeProfile(headerFontSize: 32, footerFontSize: 10);
      expect(profile.slideHeaderFontSizeAt(640), closeTo(16, 0.001));
      expect(profile.slideFooterFontSizeAt(2560), closeTo(20, 0.001));
    });
  });

  group('opslag', () {
    test('beide velden overleven toJson → fromJson', () {
      const profile = ThemeProfile(
        name: 'Huisstijl',
        headerFontSize: 24,
        footerFontSize: 12.5,
      );
      final back = ThemeProfile.fromJson(profile.toJson());
      expect(back.headerFontSize, 24);
      expect(back.footerFontSize, 12.5);
    });

    test('een profiel van vóór deze velden leest de oude maat terug', () {
      final legacy = ThemeProfile.fromJson(const {'name': 'Oud'});
      expect(legacy.headerFontSize, kSlideChromeFontSizeDefault);
      expect(legacy.footerFontSize, kSlideChromeFontSizeDefault);
    });

    test('een gekozen maat wordt op het bruikbare bereik begrensd', () {
      final tooBig = ThemeProfile.fromJson(const {'headerFontSize': 500});
      expect(tooBig.headerFontSize, kSlideChromeFontSizeMax);
      final tooSmall = ThemeProfile.fromJson(const {'footerFontSize': 1});
      expect(tooSmall.footerFontSize, kSlideChromeFontSizeMin);
    });
  });

  group('footerSafeInset', () {
    test('een grotere voettekst reserveert meer ruimte onderaan', () {
      const w = kReferenceSlideWidth;
      final slide = Slide.create(SlideType.bullets).copyWith(showFooter: true);
      const small = ThemeProfile(
        footerText: 'Confidentieel',
        footerFontSize: 8,
      );
      const large = ThemeProfile(
        footerText: 'Confidentieel',
        footerFontSize: 40,
      );

      final smallInset = footerSafeInset(w: w, slide: slide, profile: small);
      final largeInset = footerSafeInset(w: w, slide: slide, profile: large);
      expect(largeInset, greaterThan(smallInset));
      // De band bestaat uit de ondermarge plus anderhalve regel voettekst.
      expect(
        largeInset,
        closeTo(w * 0.02 + large.slideFooterFontSizeAt(w) * 1.35, 0.001),
      );
    });
  });
}
