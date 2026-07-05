import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../platform/platform_features.dart';
import '../theme/app_theme.dart';
import '../utils/display_path.dart';

/// Compacte datum (jjjj-mm-dd) voor "welke kopie is de recentste?"-context;
/// tijdstip voegt daar in een lijstregel niets aan toe.
String formatModifiedDate(DateTime? modified) {
  if (modified == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${modified.year}-${two(modified.month)}-${two(modified.day)}';
}

/// Chip "+N" bij een vermelding waarvan byte-identieke kopieën elders staan.
/// Het menu toont de andere vindplaatsen; kiezen opent die kopie.
class IdenticalCopiesChip extends StatelessWidget {
  final List<String> otherPaths;
  final String? homeDir;
  final ValueChanged<String> onOpen;

  const IdenticalCopiesChip({
    super.key,
    required this.otherPaths,
    required this.homeDir,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopupMenuButton<String>(
      tooltip: l10n.d('Identieke kopieën'),
      onSelected: onOpen,
      itemBuilder: (_) => [
        for (final path in otherPaths)
          PopupMenuItem(
            value: path,
            child: Tooltip(
              message: path,
              child: Text(
                displayFolder(path, homeDir: homeDir, osHome: osHomeDirectory),
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.copy_outlined, size: 10, color: AppTheme.accent),
            const SizedBox(width: 3),
            Text(
              '+${otherPaths.length}',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Markering voor naamgenoten met afwijkende inhoud: geen duplicaat, maar wél
/// verwarrend — de wijzigingsdatum erbij laat zien welke kopie de recentste
/// bewerking draagt.
class TitleConflictMarker extends StatelessWidget {
  final DateTime? modified;

  const TitleConflictMarker({super.key, required this.modified});

  static const _amber = AppTheme.amber700;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final date = formatModifiedDate(modified);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.difference_outlined, size: 11, color: _amber),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            date.isEmpty
                ? l10n.d('Zelfde titel, andere inhoud')
                : '${l10n.d('Zelfde titel, andere inhoud')}  ·  $date',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _amber,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
