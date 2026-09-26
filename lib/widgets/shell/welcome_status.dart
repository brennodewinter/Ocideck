// Part of the app_shell library — see ../app_shell.dart.
// Het statuscentrum linksonder op het welkomscherm: subtiele lampjes voor de
// optionele verbindingen (AI-backend, eLearning, opslag), met de uitleg in een
// hover-ballon. Losgetrokken uit welcome_screen.dart voor de groottegrens.
// Het lampje zelf — StatusChip met StatusLevel — staat gedeeld in
// connection_status.dart; de leeromgeving gebruikt hetzelfde.
part of '../app_shell.dart';

/// De statuslampjes in de voettekst van het welkomscherm. Alleen de
/// verbindingen die de gebruiker daadwerkelijk heeft ingesteld verschijnen —
/// wie AI, eLearning of een externe opslagplek niet gebruikt, ziet geen
/// doodgeknipte lampjes maar gewoon niets.
class _WelcomeStatusCenter extends ConsumerWidget {
  const _WelcomeStatusCenter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // De chip gate intern ook, maar zou hier dan als leeg kind toch een
    // tussenruimte in de Wrap opeten.
    final elearningOn =
        ref.watch(elearningEnabledProvider) &&
        ref.watch(ociServeProvider.select((s) => s.settings.enabled));
    final items = <Widget>[
      ..._aiStatusItem(context, ref, l10n),
      if (elearningOn)
        OciServeStatusChip(onTap: () => _openOciServeFromStatus(context, ref)),
      ..._storageStatusItems(context, ref, l10n),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: items,
    );
  }

  /// Het AI-lampje volgt [aiStatusProvider]: die peilt de gate én pingt de
  /// endpoint zelf, zodat dit scherm nooit zelf het netwerk hoeft te kennen.
  /// Een tik op het lampje hertikt meteen.
  List<Widget> _aiStatusItem(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final status = ref.watch(aiStatusProvider);
    if (status.availability == AiAvailability.hidden) return const [];
    final (level, message) = switch (status.availability) {
      AiAvailability.reachable => (StatusLevel.ok, l10n.d('AI: functioneert')),
      AiAvailability.checking => (
        StatusLevel.attention,
        l10n.d('AI: wordt gecontroleerd…'),
      ),
      AiAvailability.unreachable => (
        StatusLevel.unreachable,
        l10n.d('AI: server niet bereikbaar'),
      ),
      AiAvailability.denied => (
        StatusLevel.attention,
        _aiDenialMessage(l10n, status.denial),
      ),
      // Onmogelijk: hidden keerde hierboven al terug. De switch is exhaustief,
      // dus de arm moet er staan — de waarde doet er niet toe.
      AiAvailability.hidden => (StatusLevel.attention, ''),
    };
    return [
      StatusChip(
        icon: Icons.auto_awesome_outlined,
        level: level,
        message: message,
        onTap: () => ref.read(aiStatusProvider.notifier).recheck(),
      ),
    ];
  }

  /// Waarom de gate de AI-aanroep weigert — per reden een eigen zin, want
  /// "niet ingesteld" en "toestemming nodig" vragen om heel verschillende
  /// vervolgstappen van de gebruiker.
  String _aiDenialMessage(AppLocalizations l10n, AiGateDenial? denial) {
    return switch (denial) {
      AiGateDenial.modeNone ||
      AiGateDenial.notConfigured => l10n.d('AI: niet volledig ingesteld'),
      AiGateDenial.loopbackRequired => l10n.d(
        'AI: lokale server moet op dit apparaat draaien',
      ),
      AiGateDenial.privateNotTrusted => l10n.d(
        'AI: server niet als vertrouwd gemarkeerd',
      ),
      AiGateDenial.cloudNeedsConsent => l10n.d(
        'AI: toestemming voor uitgaand verkeer nodig',
      ),
      AiGateDenial.cloudNotConfirmed => l10n.d(
        'AI: externe dienst nog niet bevestigd',
      ),
      AiGateDenial.cloudBlockedOnWeb => l10n.d(
        'AI: niet beschikbaar in de webversie',
      ),
      AiGateDenial.disabled || null => l10n.d('AI: niet volledig ingesteld'),
    };
  }

  /// Eén lampje per ingestelde opslagverbinding. Een lokale map is per
  /// afspraak bereikbaar en staat meteen groen; remote soorten (WebDAV, S3,
  /// git) volgt [storageStatusProvider] live — dezelfde probe als de
  /// testknop op het opslag-tabblad. Een tik hertikt.
  List<Widget> _storageStatusItems(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final statuses = ref.watch(storageStatusProvider);
    final connections = ref.watch(
      settingsProvider.select((s) => s.connections),
    );
    return [
      for (final c in connections)
        if (statuses[c.id] case final reach?)
          StatusChip(
            icon: c.kind.icon,
            level: switch (reach) {
              StorageReach.reachable => StatusLevel.ok,
              StorageReach.checking => StatusLevel.attention,
              StorageReach.unreachable => StatusLevel.unreachable,
            },
            message: switch (reach) {
              StorageReach.reachable =>
                l10n
                    .d('{naam}: bereikbaar')
                    .replaceAll('{naam}', _connectionName(c)),
              StorageReach.checking =>
                l10n
                    .d('{naam}: wordt gecontroleerd…')
                    .replaceAll('{naam}', _connectionName(c)),
              StorageReach.unreachable =>
                l10n
                    .d('{naam}: niet bereikbaar')
                    .replaceAll('{naam}', _connectionName(c)),
            },
            onTap: () => ref.read(storageStatusProvider.notifier).recheck(c.id),
          ),
    ];
  }

  /// De naam die de gebruiker gaf, of de afgeleide omschrijving als die leeg
  /// is — dezelfde terugval als de lijst op het opslag-tabblad.
  String _connectionName(StorageConnection c) {
    final name = c.name.trim();
    return name.isEmpty ? c.fallbackLabel : name;
  }

  /// Dezelfde flow als [_WelcomeScreen._openOciServe]: eerst aanmelden als dat
  /// moet, dan de cursusdialoog. Gedupliceerd als top-level helper zodat deze
  /// widget niet aan de welkomscherm-klasse hoeft te hangen.
  Future<void> _openOciServeFromStatus(
    BuildContext context,
    WidgetRef ref,
  ) async {
    if (ref.read(ociServeProvider).status == OciServeStatus.authenticating) {
      return;
    }
    if (!ref.read(ociServeAuthenticatedProvider)) {
      final loggedIn = await ref.read(ociServeProvider.notifier).login();
      if (!loggedIn || !context.mounted) return;
    }
    await OciServeCoursesDialog.show(context);
  }
}
