// Part of the app_shell library — see ../app_shell.dart.
// Het statuscentrum linksonder op het welkomscherm: subtiele lampjes voor de
// optionele verbindingen (AI-backend, eLearning), met de uitleg in een
// hover-ballon. Losgetrokken uit welcome_screen.dart voor de groottegrens.
part of '../app_shell.dart';

/// Eén statuskleur, drie betekenissen — dezelfde voor elk lampje:
/// groen = werkt, oranje = aandacht/actie nodig (of controle loopt),
/// rood = server niet bereikbaar.
enum _WelcomeStatusLevel { ok, attention, unreachable }

/// De statuslampjes in de voettekst van het welkomscherm. Alleen de
/// verbindingen die de gebruiker daadwerkelijk heeft ingesteld verschijnen —
/// wie AI of eLearning niet gebruikt, ziet geen doodgeknipte lampjes maar
/// gewoon niets.
class _WelcomeStatusCenter extends ConsumerWidget {
  const _WelcomeStatusCenter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final items = <Widget>[
      ..._aiStatusItem(context, ref, l10n),
      ..._elearningStatusItem(context, ref, l10n),
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
      AiAvailability.reachable => (
        _WelcomeStatusLevel.ok,
        l10n.d('AI: functioneert'),
      ),
      AiAvailability.checking => (
        _WelcomeStatusLevel.attention,
        l10n.d('AI: wordt gecontroleerd…'),
      ),
      AiAvailability.unreachable => (
        _WelcomeStatusLevel.unreachable,
        l10n.d('AI: server niet bereikbaar'),
      ),
      AiAvailability.denied => (
        _WelcomeStatusLevel.attention,
        _aiDenialMessage(l10n, status.denial),
      ),
      // Onmogelijk: hidden keerde hierboven al terug. De switch is exhaustief,
      // dus de arm moet er staan — de waarde doet er niet toe.
      AiAvailability.hidden => (_WelcomeStatusLevel.attention, ''),
    };
    return [
      _statusChip(
        context,
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

  /// Het eLearning-lampje is pure afleiding van de sessiestate — de OciServe-
  /// notifier bewaakt de verbinding al, hier komt geen eigen netwerk bij.
  /// Een tik opent dezelfde inlog-/cursusflow als de knop in de startkolom.
  List<Widget> _elearningStatusItem(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final ociServe = ref.watch(ociServeProvider);
    if (!ref.watch(elearningEnabledProvider) || !ociServe.settings.enabled) {
      return const [];
    }
    final (level, message) = switch (ociServe.status) {
      OciServeStatus.authenticated => (
        _WelcomeStatusLevel.ok,
        l10n.d('eLearning: ingelogd'),
      ),
      OciServeStatus.loading || OciServeStatus.authenticating => (
        _WelcomeStatusLevel.attention,
        l10n.d('eLearning: aanmelden loopt…'),
      ),
      OciServeStatus.signedOut =>
        ociServe.serverUnavailable
            ? (
                _WelcomeStatusLevel.unreachable,
                l10n.d('eLearning: server niet bereikbaar'),
              )
            : ociServe.errorCode != null
            ? (
                _WelcomeStatusLevel.attention,
                l10n.d('eLearning: aanmelden mislukt'),
              )
            : (
                _WelcomeStatusLevel.attention,
                l10n.d('eLearning: niet ingelogd'),
              ),
    };
    return [
      _statusChip(
        context,
        icon: Icons.school_outlined,
        level: level,
        message: message,
        onTap: () => _openOciServeFromStatus(context, ref),
      ),
    ];
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

  /// Eén lampje: icoon in gedempte kleur met een gekleurde statusstip ernaast.
  /// De betekenis zit in de tooltip én in het Semantics-label, zodat de kleur
  /// nooit de enige drager is (WCAG: kleur alleen is geen informatie).
  Widget _statusChip(
    BuildContext context, {
    required IconData icon,
    required _WelcomeStatusLevel level,
    required String message,
    required VoidCallback onTap,
  }) {
    final dot = switch (level) {
      _WelcomeStatusLevel.ok => AppTheme.success700,
      _WelcomeStatusLevel.attention => AppTheme.amber600,
      _WelcomeStatusLevel.unreachable => AppTheme.danger600,
    };
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Tooltip(
      message: message,
      child: Semantics(
        label: message,
        button: true,
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
