part of '../ociserve_courses_dialog.dart';

/// De statusregel onderaan de leeromgeving-dialoog: hetzelfde lampje als het
/// statuscentrum op het openscherm — bereikbaarheid én inlogtoestand, live
/// uit de sessiestate. Hier is hij het scherpst: dit scherm opent alleen
/// voor wie is aangemeld, dus springt hij naar "niet ingelogd" of "niet
/// bereikbaar", dan is dat nieuws én biedt een tik meteen de weg terug.
class _OciServeConnectionFooter extends ConsumerWidget {
  const _OciServeConnectionFooter({required this.onReload});

  /// Herlaadt de inhoud van de dialoog — `_load()` van de ouderstate.
  final Future<void> Function() onReload;

  /// Tik op het lampje: niet aangemeld (meer) → opnieuw inloggen; wel
  /// aangemeld → de lijst verversen, bijvoorbeeld net na een hik in de
  /// verbinding.
  Future<void> _reconnect(WidgetRef ref) async {
    final status = ref.read(ociServeProvider).status;
    if (status == OciServeStatus.authenticating) return;
    if (status != OciServeStatus.authenticated) {
      final loggedIn = await ref.read(ociServeProvider.notifier).login();
      if (!loggedIn) return;
    }
    await onReload();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    decoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
    child: Row(children: [OciServeStatusChip(onTap: () => _reconnect(ref))]),
  );
}
