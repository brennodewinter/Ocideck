import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../models/storage_connection.dart';
import '../state/elearning_provider.dart';
import '../state/ociserve_provider.dart';
import '../theme/app_theme.dart';

/// Eén statuskleur, drie betekenissen — dezelfde voor elk lampje:
/// groen = werkt, oranje = aandacht/actie nodig (of controle loopt),
/// rood = server niet bereikbaar.
enum StatusLevel { ok, attention, unreachable }

/// Eén statuslampje: icoon in gedempte kleur met een gekleurde statusstip
/// ernaast. De betekenis zit in de tooltip én in het Semantics-label, zodat
/// de kleur nooit de enige drager is (WCAG: kleur alleen is geen informatie).
/// Voorheen privé op het welkomscherm; nu gedeeld omdat dezelfde lampjes ook
/// onderaan de leeromgeving en bij opslagverbindingen verschijnen.
class StatusChip extends StatelessWidget {
  final IconData icon;
  final StatusLevel level;
  final String message;
  final VoidCallback? onTap;

  const StatusChip({
    super.key,
    required this.icon,
    required this.level,
    required this.message,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dot = switch (level) {
      StatusLevel.ok => AppTheme.success700,
      StatusLevel.attention => AppTheme.amber600,
      StatusLevel.unreachable => AppTheme.danger600,
    };
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Tooltip(
      message: message,
      child: Semantics(
        label: message,
        button: onTap != null,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: muted),
                const SizedBox(width: 5),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pictogram per soort opslagverbinding — één mapping voor het
/// opslag-tabblad én de lampjes, zodat een nieuwe soort hier op één plek
/// een gezicht krijgt.
extension StorageConnectionKindIcon on StorageConnectionKind {
  IconData get icon => switch (this) {
    StorageConnectionKind.local => Icons.folder_outlined,
    StorageConnectionKind.webdav => Icons.cloud_outlined,
    StorageConnectionKind.s3 => Icons.inventory_2_outlined,
    StorageConnectionKind.git => Icons.account_tree_outlined,
  };
}

/// Het eLearning-lampje, pure afleiding van de sessiestate — de OciServe-
/// notifier bewaakt de verbinding al, hier komt geen eigen netwerk bij.
/// Zelfde lampje op het openscherm én onderaan de leeromgeving: de cursist
/// ziet op beide plekken of de server bereikbaar is en of hij is ingelogd.
class OciServeStatusChip extends ConsumerWidget {
  final VoidCallback? onTap;

  const OciServeStatusChip({super.key, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final ociServe = ref.watch(ociServeProvider);
    if (!ref.watch(elearningEnabledProvider) || !ociServe.settings.enabled) {
      return const SizedBox.shrink();
    }
    final (level, message) = switch (ociServe.status) {
      OciServeStatus.authenticated => (
        StatusLevel.ok,
        l10n.d('eLearning: ingelogd'),
      ),
      OciServeStatus.loading || OciServeStatus.authenticating => (
        StatusLevel.attention,
        l10n.d('eLearning: aanmelden loopt…'),
      ),
      OciServeStatus.signedOut =>
        ociServe.serverUnavailable
            ? (
                StatusLevel.unreachable,
                l10n.d('eLearning: server niet bereikbaar'),
              )
            : ociServe.errorCode != null
            ? (StatusLevel.attention, l10n.d('eLearning: aanmelden mislukt'))
            : (StatusLevel.attention, l10n.d('eLearning: niet ingelogd')),
    };
    return StatusChip(
      icon: Icons.school_outlined,
      level: level,
      message: message,
      onTap: onTap,
    );
  }
}
