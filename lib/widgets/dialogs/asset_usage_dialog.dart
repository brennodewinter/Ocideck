import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/git_settings.dart';
import '../../services/git/asset_index.dart';
import '../../theme/app_theme.dart';

/// Toont de gedeelde afbeeldingenpool (§9.3) met per afbeelding wie hem
/// aanhaalt.
///
/// De opruim-kandidaten staan er apart onder, maar alleen als de ronde compleet
/// wás. Kon één deck of één uitgebrachte versie niet gelezen worden, dan is
/// "niemand gebruikt dit" een onbewezen bewering en toont het scherm dát — geen
/// lijst. Weggooien is onomkeerbaar (P2), dus dit scherm mag nooit een kandidaat
/// noemen die het niet kan hardmaken.
///
/// Een eigen dialoogbestand en geen `part` van de app-shell: het scherm hoeft
/// alleen een [AssetIndexSnapshot] te krijgen, en zo is die regel ook los te
/// beproeven — als deel van de shell-bibliotheek was hij dat niet.
class AssetUsageDialog extends StatelessWidget {
  final AssetIndexSnapshot snapshot;
  const AssetUsageDialog({super.key, required this.snapshot});

  /// De hash ingekort tot iets wat een mens kan vergelijken.
  static String shortRef(String reference) {
    final path = GitRepoLayout.assetPathOf(reference) ?? reference;
    final name = path.split('/').last;
    return name.length > 14 ? '${name.substring(0, 10)}…${_ext(name)}' : name;
  }

  static String _ext(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot);
  }

  static String formatSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} kB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final unused = snapshot.assets.where((a) => a.isUnused).toList();

    return AlertDialog(
      title: Text(l10n.d('Afbeeldingen in de repository')),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${snapshot.assets.length} ${l10n.d('afbeeldingen in de gedeelde pool')}',
              style: TextStyle(fontSize: 12, color: AppTheme.slate400),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: snapshot.assets.isEmpty
                  ? Text(l10n.d('De pool is nog leeg.'))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: snapshot.assets.length,
                      itemBuilder: (context, i) =>
                          _row(l10n, snapshot.assets[i]),
                    ),
            ),
            const SizedBox(height: 12),
            _cleanupSection(l10n, unused),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.d('Sluiten')),
        ),
      ],
    );
  }

  Widget _row(AppLocalizations l10n, AssetUsage asset) {
    // Drie toestanden die echt verschillen: in gebruik, alleen nog in een
    // uitgebrachte versie, of nergens meer gevonden.
    final String usage;
    final Color colour;
    if (asset.decks.isNotEmpty) {
      usage = asset.decks.join(', ');
      colour = AppTheme.slate400;
    } else if (asset.releases.isNotEmpty) {
      usage =
          '${l10n.d('alleen nog in een uitgebrachte versie:')} '
          '${asset.releases.join(', ')}';
      colour = AppTheme.amber600;
    } else {
      usage = l10n.d('nergens meer gevonden');
      colour = AppTheme.dangerFg;
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(Icons.image_outlined, size: 18, color: colour),
      title: Text(
        shortRef(asset.reference),
        style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
      ),
      subtitle: Text(
        usage,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: colour),
      ),
      trailing: Text(
        formatSize(asset.size),
        style: TextStyle(fontSize: 11, color: AppTheme.slate400),
      ),
    );
  }

  /// De opruim-sectie — of de uitleg waarom die er niet is.
  Widget _cleanupSection(AppLocalizations l10n, List<AssetUsage> unused) {
    if (!snapshot.isComplete) {
      final blocked = [
        ...snapshot.unreadableDecks,
        ...snapshot.unreadableReleases,
      ];
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.amber600.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '${l10n.d('Niet te zeggen wat ongebruikt is: dit kon niet gelezen worden —')} '
          '${blocked.join(', ')}.',
          style: const TextStyle(fontSize: 11.5),
        ),
      );
    }
    if (unused.isEmpty) {
      return Text(
        l10n.d('Elke afbeelding wordt ergens gebruikt.'),
        style: TextStyle(fontSize: 11.5, color: AppTheme.slate400),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.slate400.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${unused.length} ${l10n.d('afbeeldingen worden nergens meer aangehaald — ook niet in een uitgebrachte versie. Dit is een voorstel, geen oordeel: op een andere branch kunnen ze nog in gebruik zijn.')}',
        style: const TextStyle(fontSize: 11.5),
      ),
    );
  }
}
