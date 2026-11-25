import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/settings.dart';
import '../../../theme/app_theme.dart';

/// Header and footer font sizes for the selected style surface.
/// Reports a new [ThemeProfile] so the caller stays free of `copyWith` noise.
class ChromeFontSizeSliders extends StatelessWidget {
  final ThemeProfile profile;
  final bool document;
  final ValueChanged<ThemeProfile> onProfileChanged;

  const ChromeFontSizeSliders({
    super.key,
    required this.profile,
    this.document = false,
    required this.onProfileChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (document) {
      return Column(
        children: [
          _documentSlider(true, l10n.d('Lettergrootte koptekst')),
          _documentSlider(false, l10n.d('Lettergrootte voettekst')),
        ],
      );
    }
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

  Widget _documentSlider(bool header, String label) {
    final size = profile.documentChromeFontSize(header);
    return _ChromeFontSizeSlider(
      sliderKey: Key(
        header ? 'document-header-font-size' : 'document-footer-font-size',
      ),
      label: label,
      value: size ?? kDocumentChromeScreenDefaultPt,
      min: kDocumentChromeFontSizeMin,
      max: kDocumentChromeFontSizeMax,
      onChanged: (value) => onProfileChanged(
        header
            ? profile.copyWith(documentHeaderFontSize: value)
            : profile.copyWith(documentFooterFontSize: value),
      ),
      onReset: size == null
          ? null
          : () => onProfileChanged(
              profile.copyWith(
                clearDocumentHeaderFontSize: header,
                clearDocumentFooterFontSize: !header,
              ),
            ),
    );
  }
}

/// Label left, slider middle, pt readout right — the same shape as the
/// activation-duration control so the footer section reads as one family.
class _ChromeFontSizeSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final Key? sliderKey;
  final VoidCallback? onReset;
  final ValueChanged<double> onChanged;

  const _ChromeFontSizeSlider({
    required this.label,
    required this.value,
    this.min = kSlideChromeFontSizeMin,
    this.max = kSlideChromeFontSizeMax,
    this.sliderKey,
    this.onReset,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final pt = value.clamp(min, max);
    final readout = '${pt.toStringAsFixed(1)} pt';
    return Row(
      children: [
        Icon(Icons.format_size, size: 18, color: AppTheme.slate500),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.brandFg,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Slider(
            key: sliderKey,
            min: min,
            max: max,
            divisions: ((max - min) * 2).round(),
            semanticFormatterCallback: (value) =>
                '$label, ${value.toStringAsFixed(1)} pt',
            label: readout,
            value: pt,
            onChanged: onChanged,
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
        if (sliderKey != null)
          IconButton(
            tooltip: '${context.l10n.d('Standaard')} · $label',
            onPressed: onReset,
            icon: const Icon(Icons.restart_alt, size: 18),
          ),
      ],
    );
  }
}
