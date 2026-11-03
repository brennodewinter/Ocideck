import 'package:app_appearance/app_appearance.dart' as foundation;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/theme/app_theme.dart';

void main() {
  for (final base in AppAppearanceProfile.builtIns) {
    for (final family in AppAppearanceProfile.uiFonts) {
      test(
        '${base.name} bewaart gekozen $family zonder andere stijlwijziging',
        () {
          final profile = base.copyWith(fontFamily: family);
          final original = const foundation.AppThemeBuilder(
            styleFocusIndicators: false,
            styleFilledButtons: false,
          ).build(profile);
          final theme = AppTheme.fromProfile(profile);
          expect(theme.colorScheme, original.colorScheme);
          expect(theme.dialogTheme, original.dialogTheme);
          expect(theme.elevatedButtonTheme, original.elevatedButtonTheme);
          expect(theme.filledButtonTheme, original.filledButtonTheme);
          for (final role in _roles) {
            expect(
              role(theme.textTheme),
              role(original.textTheme)?.copyWith(fontFamily: family),
            );
            expect(
              role(theme.primaryTextTheme),
              role(original.primaryTextTheme),
            );
          }
        },
      );
    }
  }
}

final _roles = <TextStyle? Function(TextTheme)>[
  (t) => t.displayLarge,
  (t) => t.displayMedium,
  (t) => t.displaySmall,
  (t) => t.headlineLarge,
  (t) => t.headlineMedium,
  (t) => t.headlineSmall,
  (t) => t.titleLarge,
  (t) => t.titleMedium,
  (t) => t.titleSmall,
  (t) => t.bodyLarge,
  (t) => t.bodyMedium,
  (t) => t.bodySmall,
  (t) => t.labelLarge,
  (t) => t.labelMedium,
  (t) => t.labelSmall,
];
