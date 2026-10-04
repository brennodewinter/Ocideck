import 'package:app_appearance/app_appearance.dart' as foundation;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/theme/appearance_contrast.dart' as local_appearance;
import 'package:ocideck/utils/color_contrast.dart' as local_color;

void main() {
  test('kleurfacade bewaart het gedeelde contract', () {
    const black = Color(0xFF000000);
    const white = Color(0xFFFFFFFF);

    expect(local_color.tryParseHexColor('#123456'), const Color(0xFF123456));
    expect(local_color.tryParseHexColor('geen kleur'), isNull);
    expect(
      local_color.contrastRatio(black, white),
      foundation.contrastRatio(black, white),
    );
    expect(
      local_color.hexContrastRatio('#000000', '#FFFFFF'),
      foundation.hexContrastRatio('#000000', '#FFFFFF'),
    );
    expect(local_color.meetsWcagAa('#777777', '#FFFFFF'), isFalse);
    expect(
      local_color.meetsWcagAa('#777777', '#FFFFFF', largeText: true),
      isTrue,
    );
    expect(
      local_color.blendedHexContrastRatio(
        '#000000',
        '#FFFFFF',
        foregroundAlpha: 0.5,
      ),
      foundation.blendedHexContrastRatio(
        '#000000',
        '#FFFFFF',
        foregroundAlpha: 0.5,
      ),
    );
    expect(
      local_color.nearestContrastingHex(
        '#BBBBBB',
        '#FFFFFF',
        minRatio: local_color.kWcagAaNormalText,
        foregroundAlpha: 0.8,
      ),
      foundation.nearestContrastingHex(
        '#BBBBBB',
        '#FFFFFF',
        minRatio: foundation.kWcagAaNormalText,
        foregroundAlpha: 0.8,
      ),
    );
    expect(local_color.kWcagAaLargeText, foundation.kWcagAaLargeText);
    expect(local_color.kWcagCriticalBodyText, foundation.kWcagCriticalBodyText);
  });

  test('uiterlijkfacade gebruikt OciDecks bestaande knopbeleid', () {
    final local = local_appearance.appearanceContrastFindings(
      AppAppearanceProfile.europa,
    );
    final shared = foundation.appearanceContrastFindings(
      AppAppearanceProfile.europa,
      builder: const foundation.AppThemeBuilder(
        styleFocusIndicators: false,
        styleFilledButtons: false,
      ),
    );

    expect(local.map(_findingSignature), shared.map(_findingSignature));
    expect(
      local_appearance.appearanceContrastProblems(AppAppearanceProfile.europa),
      isEmpty,
    );
  });
}

Object _findingSignature(foundation.AppearanceContrastFinding finding) => (
  finding.pair,
  finding.foreground,
  finding.background,
  finding.ratio,
  finding.threshold,
);
