import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Inklapbare sectie voor geavanceerde opties (progressive disclosure):
/// basisopties blijven direct zichtbaar, wat zelden nodig is zit achter één
/// rustige kop met chevron. Bewust een lichtgewicht eigen widget in de stijl
/// van [SectionLabel] — ExpansionTile sleept dividers en Material-marges mee
/// die in de compacte editors uit de toon vallen.
///
/// [title] is een reeds gelokaliseerde tekst — geef hem via de d-helper van
/// de call-site mee, zodat de l10n-test de bronstring daar ziet. Zet
/// [initiallyExpanded] op true wanneer een geavanceerde optie al een
/// niet-standaardwaarde heeft — dan is verstoppen juist verwarrend.
class AdvancedSection extends StatefulWidget {
  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  const AdvancedSection({
    super.key,
    required this.title,
    required this.children,
    this.initiallyExpanded = false,
  });

  @override
  State<AdvancedSection> createState() => _AdvancedSectionState();
}

class _AdvancedSectionState extends State<AdvancedSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: AppTheme.slate500,
                ),
                const SizedBox(width: 4),
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.slate500,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.children,
            ),
          ),
      ],
    );
  }
}
