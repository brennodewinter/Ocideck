import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/settings.dart';
import '../../../theme/app_theme.dart';

/// The two font-size sliders for slide chrome text — the Marp header and the
/// footer — in points on a 1280-wide slide (see [ThemeProfile.headerFontSize]).
/// Reports a new [ThemeProfile] so the caller stays free of `copyWith` noise.
class ChromeFontSizeSliders extends StatelessWidget {
  final ThemeProfile profile;
  final ValueChanged<ThemeProfile> onProfileChanged;

  const ChromeFontSizeSliders({
    super.key,
    required this.profile,
    required this.onProfileChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        _ChromeFontSizeSlider(
          label: l10n.d('Lettergrootte koptekst'),
          value: profile.headerFontSize,
          onChanged: (v) =>
              onProfileChanged(profile.copyWith(headerFontSize: v)),
        ),
        _ChromeFontSizeSlider(
          label: l10n.d('Lettergrootte voettekst'),
          value: profile.footerFontSize,
          onChanged: (v) =>
              onProfileChanged(profile.copyWith(footerFontSize: v)),
        ),
      ],
    );
  }
}

/// Label left, slider middle, pt readout right — the same shape as the
/// activation-duration control so the footer section reads as one family.
class _ChromeFontSizeSlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _ChromeFontSizeSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final pt = clampSlideChromeFontSize(value);
    final readout = '${pt.toStringAsFixed(1)} pt';
    return Row(
      children: [
        Icon(Icons.format_size, size: 18, color: AppTheme.slate500),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.brandFg,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Slider(
            min: kSlideChromeFontSizeMin,
            max: kSlideChromeFontSizeMax,
            divisions: ((kSlideChromeFontSizeMax - kSlideChromeFontSizeMin) * 2)
                .round(),
            label: readout,
            value: pt,
            onChanged: (v) => onChanged(clampSlideChromeFontSize(v)),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            readout,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.slate500,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
