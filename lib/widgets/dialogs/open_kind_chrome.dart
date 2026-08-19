import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/markdown_kind.dart';
import '../../theme/app_theme.dart';

/// Het gedeelde beeld van "wat voor bestand is dit" in de openschermen.
///
/// Sinds het openscherm ook platte documenten toont, staan er twee soorten in
/// één lijst. Wie een rij ziet moet zonder hem te openen kunnen zien wat het is
/// — anders klik je een presentatie aan terwijl je een document zocht, en merk
/// je dat pas als de editor er staat. Icoon, label en filter horen daarom bij
/// elkaar en wonen op één plek: de mapzoeker en de brede schijfzoeker tonen
/// hetzelfde, en een derde lijst erbij erft het.
enum OpenKindFilter {
  /// Presentaties én documenten.
  all,

  /// Alleen Marp/OciDeck-presentaties.
  presentations,

  /// Alleen platte Markdown-documenten.
  documents;

  /// Of een bestand van soort [kind] bij dit filter hoort.
  bool accepts(MarkdownKind kind) => switch (this) {
    OpenKindFilter.all => true,
    OpenKindFilter.presentations => kind.isPresentation,
    OpenKindFilter.documents => kind.isDocument,
  };
}

/// Het pictogram van een soort: dezelfde dia in elk overzicht, hetzelfde blad
/// voor elk document.
IconData markdownKindIcon(MarkdownKind kind) =>
    kind.isDocument ? Icons.article_outlined : Icons.slideshow_outlined;

/// De naam van een soort, in de taal van de gebruiker.
String markdownKindLabel(AppLocalizations l10n, MarkdownKind kind) =>
    kind.isDocument ? l10n.d('Document') : l10n.d('Presentatie');

/// Het soortlabel als klein vlagje achter een titel in een lijstrij.
class MarkdownKindBadge extends StatelessWidget {
  const MarkdownKindBadge({super.key, required this.kind});

  final MarkdownKind kind;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Document en presentatie krijgen elk hun eigen tint, maar allebei op de
    // rustige kant: het vlagje ordent de lijst, het vraagt geen aandacht.
    final color = kind.isDocument ? AppTheme.tealFg : AppTheme.brandFg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        markdownKindLabel(l10n, kind),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// De keuzebalk "Alles · Presentaties · Documenten" boven een resultatenlijst.
///
/// De aantallen staan in het label: zo zie je dat er documenten gevonden zijn
/// zonder eerst op het filter te hoeven klikken — en zie je bij nul dat er
/// niets is, in plaats van een leeg scherm na een klik.
class OpenKindFilterBar extends StatelessWidget {
  const OpenKindFilterBar({
    super.key,
    required this.value,
    required this.onChanged,
    required this.presentationCount,
    required this.documentCount,
  });

  final OpenKindFilter value;
  final ValueChanged<OpenKindFilter> onChanged;
  final int presentationCount;
  final int documentCount;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        _chip(
          context,
          OpenKindFilter.all,
          l10n.d('Alles'),
          presentationCount + documentCount,
        ),
        _chip(
          context,
          OpenKindFilter.presentations,
          l10n.d('Presentaties'),
          presentationCount,
        ),
        _chip(
          context,
          OpenKindFilter.documents,
          l10n.d('Documenten'),
          documentCount,
        ),
      ],
    );
  }

  Widget _chip(
    BuildContext context,
    OpenKindFilter filter,
    String label,
    int count,
  ) {
    return ChoiceChip(
      label: Text('$label ($count)', style: const TextStyle(fontSize: 11)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      selected: value == filter,
      onSelected: (_) => onChanged(filter),
    );
  }
}
