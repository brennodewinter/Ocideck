import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/page_size.dart';

/// De diaformaat-keuze uit de presentatie-info-dialoog (#2433): de
/// schermstandaard 16:9 of een ISO-papierformaat. De keuze wordt als
/// `papersize`/`geometry` in de front matter opgeslagen en geldt voor
/// editor, strook, presentatie en exports.
///
/// `null` betekent de schermstandaard; een [PageSizeSpec] staat via het
/// reeks/maat/richting-raster — dezelfde drie dropdowns als de
/// documentpagina-instelling.
class SlideSizePicker extends StatelessWidget {
  const SlideSizePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final PageSizeSpec? value;
  final ValueChanged<PageSizeSpec?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final size = value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<bool>(
          key: const ValueKey('slide-size-kind'),
          initialValue: size != null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.d('Diaformaat'),
            border: const OutlineInputBorder(),
            helperText: l10n.d(
              'Kies een papierformaat voor hand-outs en exports op papier.',
            ),
          ),
          items: [
            DropdownMenuItem(
              value: false,
              child: Text(l10n.d('Scherm (16:9)')),
            ),
            DropdownMenuItem(value: true, child: Text(l10n.d('Papierformaat'))),
          ],
          onChanged: (v) =>
              onChanged(v == true ? (value ?? PageSizeSpec.a4Landscape) : null),
        ),
        if (size != null) ...[
          const SizedBox(height: 8),
          _paperSizeRow(l10n, size),
        ],
      ],
    );
  }

  /// Reeks, maat en richting van het gekozen papierformaat — hetzelfde
  /// ISO-216-raster als de documentpagina-instelling.
  Widget _paperSizeRow(AppLocalizations l10n, PageSizeSpec size) {
    void set(PageSizeSpec next) => onChanged(next);
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<PaperSeries>(
            initialValue: size.series,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.d('Reeks'),
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final series in PaperSeries.values)
                DropdownMenuItem(
                  value: series,
                  child: Text(series.name.toUpperCase()),
                ),
            ],
            onChanged: (v) => v == null
                ? null
                : set(
                    PageSizeSpec(
                      series: v,
                      number: size.number,
                      landscape: size.landscape,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<int>(
            initialValue: size.number,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.d('Maat'),
              border: const OutlineInputBorder(),
            ),
            items: [
              for (var n = 0; n <= 10; n++)
                DropdownMenuItem(
                  value: n,
                  child: Text(
                    _slideSizeLabel(
                      PageSizeSpec(series: size.series, number: n),
                    ),
                  ),
                ),
            ],
            onChanged: (v) => v == null
                ? null
                : set(
                    PageSizeSpec(
                      series: size.series,
                      number: v,
                      landscape: size.landscape,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<bool>(
            key: const ValueKey('slide-size-orientation'),
            initialValue: size.landscape,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.d('Richting'),
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(value: false, child: Text(l10n.d('Staand'))),
              DropdownMenuItem(value: true, child: Text(l10n.d('Liggend'))),
            ],
            onChanged: (v) => v == null
                ? null
                : set(
                    PageSizeSpec(
                      series: size.series,
                      number: size.number,
                      landscape: v,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  /// Bijv. `"A4 — 210 × 297 mm"`: de maatnaam plus zijn afmeting.
  static String _slideSizeLabel(PageSizeSpec spec) {
    final (w, h) = spec.dimensions;
    return '${spec.sizeName} — ${w.toStringAsFixed(0)} × '
        '${h.toStringAsFixed(0)} mm';
  }
}
