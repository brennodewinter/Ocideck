// Compatibiliteitsfacade; de contrastmeting zelf is productneutraal.
import 'package:app_appearance/app_appearance.dart' as foundation;

import '../models/settings.dart';

typedef AppearanceContrastFinding = foundation.AppearanceContrastFinding;
typedef AppearanceContrastPair = foundation.AppearanceContrastPair;

/// Meet de gedeelde contrastparen met OciDecks bestaande knopbeleid.
List<AppearanceContrastFinding> appearanceContrastFindings(
  AppAppearanceProfile profile,
) => foundation.appearanceContrastFindings(
  profile,
  builder: const foundation.AppThemeBuilder(
    styleFocusIndicators: false,
    styleFilledButtons: false,
  ),
);

/// Alleen de gedeelde contrastmetingen die OciDecks norm niet halen.
List<AppearanceContrastFinding> appearanceContrastProblems(
  AppAppearanceProfile profile,
) => foundation.appearanceContrastProblems(
  profile,
  builder: const foundation.AppThemeBuilder(
    styleFocusIndicators: false,
    styleFilledButtons: false,
  ),
);
