import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/asset_origin.dart';
import '../theme/app_theme.dart';

/// Maakt zichtbaar wat er met de media van een slide gebeurt zodra de
/// presentatie naar iemand anders gaat.
///
/// De aanleiding: een verwijzing naar een bestand elders op de schijf werkt bij
/// de maker prima en is bij de ontvanger een gat, en dat verschil was nergens
/// af te lezen — de slide toonde in beide gevallen gewoon de afbeelding. De
/// badge zegt daarom niet waar het bestand staat, maar wat dat betekent.
///
/// Bewust alleen in de editor en het kwaliteitspaneel, niet op de gerenderde
/// slide: die render is ook wat het publiek en de export te zien krijgen, en
/// daar hoort geen werkinstructie in.
class AssetOriginBadge extends StatelessWidget {
  final AssetOrigin origin;

  const AssetOriginBadge({super.key, required this.origin});

  @override
  Widget build(BuildContext context) {
    if (!assetOriginNeedsAttention(origin)) return const SizedBox.shrink();
    final l10n = context.l10n;
    final (icon, color) = _appearance(origin);

    return Tooltip(
      message: assetOriginExplanation(l10n, origin),
      // De uitleg is een hele zin; laat hem afbreken in plaats van uitwaaieren.
      textAlign: TextAlign.start,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              assetOriginLabel(l10n, origin),
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Icoon en kleur per herkomst. De wachtkamer is blauw: er is niets mis, het
  /// is alleen nog niet af. De rest is amber — daar moet de gebruiker iets
  /// voor doen wil de presentatie elders werken.
  (IconData, Color) _appearance(AssetOrigin origin) => switch (origin) {
    AssetOrigin.staged => (Icons.schedule_outlined, AppTheme.blue500),
    AssetOrigin.external => (Icons.link_off, AppTheme.amber600),
    AssetOrigin.remote => (Icons.cloud_outlined, AppTheme.amber600),
    AssetOrigin.memory => (Icons.memory_outlined, AppTheme.amber600),
    AssetOrigin.none || AssetOrigin.inDeck => (Icons.check, AppTheme.blue500),
  };
}

/// Korte aanduiding voor op de badge.
String assetOriginLabel(AppLocalizations l10n, AssetOrigin origin) =>
    switch (origin) {
      AssetOrigin.staged => l10n.d('Nog niet opgeslagen'),
      AssetOrigin.external => l10n.d('Buiten de presentatie'),
      AssetOrigin.remote => l10n.d('Van internet'),
      AssetOrigin.memory => l10n.d('Alleen in deze sessie'),
      AssetOrigin.none || AssetOrigin.inDeck => '',
    };

/// De hele zin: wat er gebeurt, en wat de gebruiker eraan kan doen. Een badge
/// die alleen een toestand noemt waarschuwt nergens voor.
String assetOriginExplanation(AppLocalizations l10n, AssetOrigin origin) =>
    switch (origin) {
      AssetOrigin.staged => l10n.d(
        'Dit bestand is al gekopieerd en staat veilig. Het krijgt zijn plek in de presentatiemap zodra u opslaat.',
      ),
      AssetOrigin.external => l10n.d(
        'Dit bestand ligt buiten de presentatiemap en gaat niet mee. Wie de presentatie van u krijgt, ziet hier niets. Sla op om een kopie te maken.',
      ),
      AssetOrigin.remote => l10n.d(
        'Dit bestand staat op internet en hoort niet bij de presentatie. Zonder verbinding, of als de bron verdwijnt, is het weg.',
      ),
      AssetOrigin.memory => l10n.d(
        'In de webversie blijft dit bestand alleen in het geheugen van deze sessie. Na het herladen van de pagina is het weg.',
      ),
      AssetOrigin.none || AssetOrigin.inDeck => '',
    };
