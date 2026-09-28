import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../models/storage_connection.dart';
import '../state/elearning_provider.dart';
import '../state/ociserve_provider.dart';
import '../state/storage_status_provider.dart';
import '../theme/app_theme.dart';

/// Eén statuskleur, drie betekenissen — dezelfde voor elk lampje:
/// groen = werkt, oranje = aandacht/actie nodig (of controle loopt),
/// rood = server niet bereikbaar.
enum StatusLevel { ok, attention, unreachable }

/// De drie betekeniskleuren — gedeeld door chip en stip, zodat een nieuwe
/// statuskleur maar één plek heeft.
Color statusLevelColor(StatusLevel level) => switch (level) {
  StatusLevel.ok => AppTheme.success700,
  StatusLevel.attention => AppTheme.amber600,
  StatusLevel.unreachable => AppTheme.danger600,
};

/// Alleen de gekleurde stip — voor rijen waar het icoon er al staat, zoals
/// de verbindingslijst op het opslag-tabblad. De uitleg hoort in de
/// [tooltip] (en in de Semantics van het geheel eromheen).
class StatusDot extends StatelessWidget {
  final StatusLevel level;
  final String? tooltip;

  const StatusDot({super.key, required this.level, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: statusLevelColor(level),
        shape: BoxShape.circle,
      ),
    );
    final message = tooltip;
    return message == null ? dot : Tooltip(message: message, child: dot);
  }
}

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
                StatusDot(level: level),
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
/// ziet op beide plekken de hele ketting — server ingesteld, account
/// ingesteld, server bereikbaar, ingelogd. De ballon somt die checks onder
/// elkaar op, zoals het opslaglampje dat per verbinding doet. Zichtbaar
/// zodra de module aan staat — óók zonder ingestelde server, want juist dán
/// is er wat te melden. Over bereikbaarheid is alleen iets bekend ná een
/// poging: wie nog nooit aanmeldde, krijgt geen bereikbaarheidsregel en dus
/// geen schijnzekerheid.
class OciServeStatusChip extends ConsumerWidget {
  final VoidCallback? onTap;

  const OciServeStatusChip({super.key, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final ociServe = ref.watch(ociServeProvider);
    // Beide eLearning-schakelaars tellen: "maken" (module) én "volgen"
    // (de OciServe-koppeling — settings.enabled). Zonder één van beide is
    // er niets om naar een server te laten verwijzen.
    if (!ref.watch(elearningEnabledProvider) && !ociServe.settings.enabled) {
      return const SizedBox.shrink();
    }
    // De regels hergebruiken de opslag-templates: 'eLearning-server' en
    // 'eLearning-account' zijn daar gewoon namen als elke andere.
    String line(String template, String naam) =>
        l10n.d(template).replaceAll('{naam}', naam);
    final serverSet =
        ociServe.settings.enabled && ociServe.settings.isConfigured;
    final accountSet = ociServe.authenticated || ociServe.hasStoredLogin;
    String accountLine() => line(
      accountSet ? '{naam}: ingesteld' : '{naam}: niet ingesteld',
      'eLearning-account',
    );
    final (level, lines) = switch (ociServe.status) {
      // Zonder ingestelde server is er niets om te laden of aan te melden —
      // de ketting begint daar al stuk.
      _ when !serverSet => (
        StatusLevel.attention,
        [
          line('{naam}: niet ingesteld', 'eLearning-server'),
          line('{naam}: niet ingesteld', 'eLearning-account'),
          l10n.d('eLearning: niet ingelogd'),
        ],
      ),
      // Tijdens laden/aanmelden is over geen enkele schakel iets bekend.
      OciServeStatus.loading || OciServeStatus.authenticating => (
        StatusLevel.attention,
        [
          line('{naam}: wordt gecontroleerd…', 'eLearning-server'),
          l10n.d('eLearning: aanmelden loopt…'),
        ],
      ),
      OciServeStatus.authenticated => (
        StatusLevel.ok,
        [
          line('{naam}: bereikbaar', 'eLearning-server'),
          accountLine(),
          l10n.d('eLearning: ingelogd'),
        ],
      ),
      OciServeStatus.signedOut =>
        ociServe.serverUnavailable
            ? (
                StatusLevel.unreachable,
                [
                  line('{naam}: niet bereikbaar', 'eLearning-server'),
                  accountLine(),
                  l10n.d('eLearning: niet ingelogd'),
                ],
              )
            : ociServe.errorCode != null
            // Een geweigerde aanmelding bewijst juist dat de server
            // antwoordde — de serverregel zegt dan "bereikbaar".
            ? (
                StatusLevel.attention,
                [
                  line('{naam}: bereikbaar', 'eLearning-server'),
                  accountLine(),
                  l10n.d('eLearning: aanmelden mislukt'),
                ],
              )
            : (
                StatusLevel.attention,
                [
                  // Bereikt zonder poging: de server is wel ingesteld maar
                  // over bereikbaarheid is (nog) niets bekend.
                  line('{naam}: ingesteld', 'eLearning-server'),
                  accountLine(),
                  l10n.d('eLearning: niet ingelogd'),
                ],
              ),
    };
    return StatusChip(
      icon: Icons.school_outlined,
      level: level,
      message: lines.join('\n'),
      onTap: onTap,
    );
  }
}

/// De live-bereikbaarheid van één opslagverbinding als enkele stip — dezelfde
/// provider en kleuren als het geaggregeerde lampje op het openscherm, voor
/// de rijen op het opslag-tabblad waar icoon en naam er al staan. Niets voor
/// wat de provider overslaat (niet ingesteld, remote op web): dan ontbreekt
/// de stip gewoon, zoals het lampje dan ook ontbreekt.
class StorageStatusDot extends ConsumerWidget {
  final StorageConnection connection;

  const StorageStatusDot({super.key, required this.connection});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reach = ref.watch(
      storageStatusProvider.select((m) => m[connection.id]),
    );
    if (reach == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final name = connection.name.trim();
    final label = name.isEmpty ? connection.fallbackLabel : name;
    final (level, message) = switch (reach) {
      StorageReach.reachable => (
        StatusLevel.ok,
        l10n.d('{naam}: bereikbaar').replaceAll('{naam}', label),
      ),
      StorageReach.checking => (
        StatusLevel.attention,
        l10n.d('{naam}: wordt gecontroleerd…').replaceAll('{naam}', label),
      ),
      StorageReach.unreachable => (
        StatusLevel.unreachable,
        l10n.d('{naam}: niet bereikbaar').replaceAll('{naam}', label),
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: StatusDot(level: level, tooltip: message),
    );
  }
}
