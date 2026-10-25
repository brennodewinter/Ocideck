// De vergaderlink-controle (#2533) — het eerste gebruikerszichtbare stuk van
// de call-keten. Twee bewust gescheiden stappen:
//
//   1. "Controleer" — de resolver, puur lokaal. Herkent een provider de link
//      (eigen trusted host of een goedgekeurd profiel), dan mag preflight.
//      Herkent niemand hem maar LIJKT hij op een meeting, dan volgt de enige
//      vraag die §7.1.6 toestaat: "welke vergaderdienst is dit?" — de
//      gebruiker beslist, nooit de URL-vorm. Bij die keuze kan de gebruiker
//      de herkomst als profiel onthouden, mét het expliciete vertrouwens-
//      besluit "staat op mijn eigen netwerk" (trustedInternal).
//   2. "Preflight" — het eerste netwerkmoment, achter een knop die zegt welke
//      oorsprong benaderd wordt. Resultaat: getypeerde support + redenen,
//      identiteit, E2EE-status en de egress-lijst.
//   3. "Deelnemen" (#2534) — alleen bij `canJoin`; start de echte sessie en
//      draagt hem over aan `meetingSessionProvider` (root-scoped). Een
//      mislukte join toont de getypeerde reden in hetzelfde dialoog.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../state/meeting_providers.dart';
import '../../theme/app_theme.dart';
import '../../meetings/meeting_link_resolver.dart';
import '../../meetings/meeting_provider.dart';
import '../../meetings/meeting_nick.dart';
import '../../meetings/meeting_provider_profile.dart';
import '../../state/meeting_session_provider.dart';
import '../../utils/literal_loopback.dart' show isLiteralInternalHost;
import '../../utils/log.dart';
import '../../utils/net_guard.dart';

/// Injecteerbare preflight — tests hoeven geen XMPP-stack.
typedef MeetingPreflightFn =
    Future<MeetingPreflight> Function(MeetingLinkMatch match);

/// Injecteerbaar profiel-opslag — tests hoeven geen SharedPreferences.
typedef MeetingProfileSaveFn =
    Future<void> Function(MeetingProviderProfile profile);

/// Injecteerbare join — tests hoeven geen XMPP/WebRTC-stack.
typedef MeetingJoinFn = Future<MeetingSession> Function(MeetingJoinRequest);

class MeetingPreflightDialog extends ConsumerStatefulWidget {
  const MeetingPreflightDialog({
    super.key,
    this.resolver,
    this.preflight,
    this.join,
    this.saveProfile,
  });

  /// Tests steken een eigen resolver in; null leest de provider-wiring.
  final MeetingLinkResolver? resolver;
  final MeetingPreflightFn? preflight;
  final MeetingJoinFn? join;
  final MeetingProfileSaveFn? saveProfile;

  @override
  ConsumerState<MeetingPreflightDialog> createState() =>
      _MeetingPreflightDialogState();
}

class _MeetingPreflightDialogState
    extends ConsumerState<MeetingPreflightDialog> {
  final _link = TextEditingController();
  MeetingLinkResolution? _resolution;
  MeetingLinkMatch? _match;
  bool _askingProvider = false;
  bool _rememberProfile = false;
  bool _trustedInternal = false;
  bool _preflighting = false;
  MeetingPreflight? _preflight;
  bool _joining = false;
  MeetingFailureReason? _joinError;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  MeetingLinkResolver get _resolver =>
      widget.resolver ?? ref.read(meetingLinkResolverProvider);

  Future<MeetingPreflight> _runPreflight(MeetingLinkMatch match) =>
      widget.preflight != null
      ? widget.preflight!(match)
      : ref
            .read(meetingProvidersProvider)
            .firstWhere((p) => p.id == match.providerId)
            .preflight(match);

  void _resolve() {
    final resolution = _resolver.resolve(_link.text);
    setState(() {
      _resolution = resolution;
      _match = resolution.match;
      _askingProvider =
          resolution.verdict == MeetingLinkVerdict.unrecognized &&
          resolution.looksLikeMeeting;
      _rememberProfile = false;
      _trustedInternal = false;
      _preflight = null;
      _joinError = null;
    });
  }

  /// De gebruiker vertelde welke dienst het is (Jitsi) — bouw de match en
  /// bewaar eventueel het profiel. Alleen de aangevinkte
  /// trustedInternal-beslissing reist mee; de URL-structuur deed niets.
  Future<void> _chooseProvider(String providerId) async {
    final normalized = _resolution!.normalized!;
    final origin = Uri(
      scheme: normalized.scheme,
      host: normalized.host,
      port: normalized.hasPort ? normalized.port : null,
    );
    // Het vertrouwensbesluit geldt ook zonder onthouden: een interne server
    // heeft trustedInternal nú nodig, niet pas bij een volgende link.
    final profile = MeetingProviderProfile(
      id: '',
      providerId: providerId,
      origin: origin,
      trustedInternal: _trustedInternal,
    );
    if (_rememberProfile) {
      final save =
          widget.saveProfile ??
          ref.read(meetingProfilesProvider.notifier).upsert;
      await save(profile);
      if (!mounted) return;
    }
    setState(() {
      _askingProvider = false;
      _match = MeetingLinkMatch(
        providerId: providerId,
        invitation: normalized,
        viaProfile: profile,
      );
    });
  }

  Future<void> _preflightNow() async {
    setState(() => _preflighting = true);
    try {
      final result = await _runPreflight(_match!);
      if (!mounted) return;
      setState(() {
        _preflighting = false;
        _preflight = result;
        _joinError = null;
      });
    } on Object catch (e, st) {
      logError('MeetingPreflightDialog: preflight', e, st);
      if (!mounted) return;
      setState(() {
        _preflighting = false;
        _joinError = MeetingFailureReason.providerUnavailable;
      });
    }
  }

  Future<MeetingSession> _runJoin() => widget.join != null
      ? widget.join!(
          MeetingJoinRequest(
            link: _match!,
            displayName: _preflight!.identityLabel ?? uniqueMeetingNick(),
          ),
        )
      : ref
            .read(meetingProvidersProvider)
            .firstWhere((p) => p.id == _match!.providerId)
            .join(
              MeetingJoinRequest(
                link: _match!,
                displayName: _preflight!.identityLabel ?? uniqueMeetingNick(),
              ),
            );

  /// De echte deelname. Een sessie die terugkomt is live (het contract garan-
  /// deert een mediapad); elke weigering komt terug als getypeerde reden.
  Future<void> _joinNow() async {
    setState(() {
      _joining = true;
      _joinError = null;
    });
    try {
      final session = await _runJoin();
      ref.read(meetingSessionProvider.notifier).adopt(session);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on MeetingJoinException catch (e) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _joinError = e.reason;
      });
    } on Object catch (e, st) {
      logError('MeetingPreflightDialog: join', e, st);
      if (!mounted) return;
      setState(() {
        _joining = false;
        _joinError = MeetingFailureReason.providerUnavailable;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.d('Vergaderlink controleren')),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Plak een link naar een vergadering. OciDeck controleert eerst lokaal welke dienst dit is; alleen als u om een preflight vraagt wordt er verbinding gemaakt met de server.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _link,
              decoration: InputDecoration(
                labelText: l10n.d('Vergaderlink'),
                hintText: l10n.d('https://meet.jit.si/kamernaam'),
              ),
              onSubmitted: (_) => _resolve(),
            ),
            if (_resolution != null) ...[
              const SizedBox(height: 14),
              _ResolutionView(
                l10n: l10n,
                resolution: _resolution!,
                match: _match,
                askingProvider: _askingProvider,
                rememberProfile: _rememberProfile,
                trustedInternal: _trustedInternal,
                onRememberChanged: (v) => setState(() => _rememberProfile = v),
                onTrustedChanged: (v) => setState(() => _trustedInternal = v),
                onChooseProvider: _chooseProvider,
              ),
            ],
            if (_preflight != null) ...[
              const SizedBox(height: 14),
              _PreflightView(l10n: l10n, preflight: _preflight!),
            ],
            if (ref.watch(meetingSessionProvider) != null &&
                (_preflight?.canJoin ?? false)) ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: AppTheme.slate600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.d(
                        'U neemt al deel aan een vergadering; die wordt verlaten als u nu deelneemt.',
                      ),
                      style: TextStyle(fontSize: 12, color: AppTheme.slate600),
                    ),
                  ),
                ],
              ),
            ],
            if (_joinError != null) ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 18, color: AppTheme.dangerFg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _PreflightView.failureText(l10n, _joinError!),
                      style: TextStyle(fontSize: 12, color: AppTheme.dangerFg),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Text(
              l10n.d(
                'Bij deelname gebruikt OciDeck uw microfoon en (optioneel) camera; u start gedempt.',
              ),
              style: TextStyle(fontSize: 11, color: AppTheme.slate600),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _preflighting || _joining
              ? null
              : () => Navigator.of(context).pop(),
          child: Text(l10n.d('Sluiten')),
        ),
        if (_preflight?.canJoin ?? false)
          FilledButton(
            onPressed: _joining ? null : _joinNow,
            child: Text(_joining ? l10n.d('Verbinden…') : l10n.d('Deelnemen')),
          )
        else if (_match != null && _preflight == null)
          FilledButton(
            onPressed: _preflighting ? null : _preflightNow,
            child: Text(
              _preflighting
                  ? l10n.d('Verbinden…')
                  : l10n.d('Preflight uitvoeren'),
            ),
          )
        else
          FilledButton(onPressed: _resolve, child: Text(l10n.d('Controleer'))),
      ],
    );
  }
}

/// De uitkomst van de lokale resolutie: geweigerd, onbekend (+ de
/// provider-vraag), of herkend.
class _ResolutionView extends StatelessWidget {
  const _ResolutionView({
    required this.l10n,
    required this.resolution,
    required this.match,
    required this.askingProvider,
    required this.rememberProfile,
    required this.trustedInternal,
    required this.onRememberChanged,
    required this.onTrustedChanged,
    required this.onChooseProvider,
  });

  final AppLocalizations l10n;
  final MeetingLinkResolution resolution;
  final MeetingLinkMatch? match;
  final bool askingProvider;
  final bool rememberProfile;
  final bool trustedInternal;
  final ValueChanged<bool> onRememberChanged;
  final ValueChanged<bool> onTrustedChanged;
  final void Function(String providerId) onChooseProvider;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (resolution.carriedCredential)
          _line(
            Icons.key_off_outlined,
            AppTheme.slate600,
            l10n.d(
              'De link droeg een inlogtoken; die is verwijderd en wordt niet bewaard.',
            ),
          ),
        switch (resolution.verdict) {
          MeetingLinkVerdict.invalid => _line(
            Icons.error_outline,
            AppTheme.dangerFg,
            _invalidText(l10n, resolution.invalidReason!),
          ),
          MeetingLinkVerdict.recognized => _line(
            Icons.check_circle_outline,
            AppTheme.successFg,
            match?.viaProfile != null
                ? '${l10n.d('Herkend als Jitsi-vergadering via uw goedgekeurde server')}: '
                      '${match!.viaProfile!.origin}'
                : l10n.d(
                    'Herkend als Jitsi-vergadering (meet.jit.si). Preflight haalt de gegevens van de server op.',
                  ),
          ),
          MeetingLinkVerdict.unrecognized when !askingProvider => _line(
            Icons.help_outline,
            AppTheme.slate600,
            l10n.d(
              'OciDeck herkent deze link niet als een vergadering van een ondersteunde dienst.',
            ),
          ),
          MeetingLinkVerdict.unrecognized => _ProviderQuestion(
            l10n: l10n,
            origin: resolution.normalized!,
            rememberProfile: rememberProfile,
            trustedInternal: trustedInternal,
            onRememberChanged: onRememberChanged,
            onTrustedChanged: onTrustedChanged,
            onChooseProvider: onChooseProvider,
          ),
        },
      ],
    );
  }

  static String _invalidText(
    AppLocalizations l10n,
    MeetingLinkInvalidReason reason,
  ) => switch (reason) {
    MeetingLinkInvalidReason.notAUrl => l10n.d('Dit is geen geldige link.'),
    MeetingLinkInvalidReason.unsupportedScheme => l10n.d(
      'Alleen http(s)-links kunnen een vergadering zijn.',
    ),
    MeetingLinkInvalidReason.containsCredentials => l10n.d(
      'Deze link bevat een inlognaam of wachtwoord; dat wordt niet gebruikt.',
    ),
  };

  Widget _line(IconData icon, Color color, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 12, color: color)),
        ),
      ],
    ),
  );
}

/// De enige vraag die een hint mag opleveren: welke dienst is dit? Met het
/// onthoud-aanbod + het expliciete interne-netwerk-besluit.
class _ProviderQuestion extends StatelessWidget {
  const _ProviderQuestion({
    required this.l10n,
    required this.origin,
    required this.rememberProfile,
    required this.trustedInternal,
    required this.onRememberChanged,
    required this.onTrustedChanged,
    required this.onChooseProvider,
  });

  final AppLocalizations l10n;
  final Uri origin;
  final bool rememberProfile;
  final bool trustedInternal;
  final ValueChanged<bool> onRememberChanged;
  final ValueChanged<bool> onTrustedChanged;
  final void Function(String providerId) onChooseProvider;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.d(
            'Deze link wordt niet automatisch herkend. Welke vergaderdienst gebruikt deze server?',
          ),
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.video_camera_front_outlined, size: 16),
              label: Text(l10n.d('Jitsi')),
              onPressed: () => onChooseProvider('jitsi'),
            ),
          ],
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: rememberProfile,
          onChanged: (v) => onRememberChanged(v ?? false),
          title: Text(
            '${l10n.d('Onthoud deze server als Jitsi-deployment')}: '
            '${origin.scheme}://${origin.authority}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: trustedInternal,
          onChanged: (v) => onTrustedChanged(v ?? false),
          title: Text(
            // Op web gooit NetGuard.isBlockedHost (`InternetAddress.tryParse`).
            // Dezelfde letterlijke classificatie, zonder dart:io. Een gewone
            // naam blijft hier "publiek": die lost de browser op.
            (kIsWeb
                    ? isLiteralInternalHost(origin.host)
                    : NetGuard.isBlockedHost(origin.host))
                ? l10n.d(
                    'Deze server staat op mijn eigen (interne) netwerk — privé-adres, alleen aanvinken als u deze server beheert',
                  )
                : l10n.d('Deze server staat op mijn eigen (interne) netwerk'),
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// De preflight-feiten: support, identiteit, E2EE en waar het verkeer heen
/// gaat — getypeerd, met detail bij falen.
class _PreflightView extends StatelessWidget {
  const _PreflightView({required this.l10n, required this.preflight});

  final AppLocalizations l10n;
  final MeetingPreflight preflight;

  @override
  Widget build(BuildContext context) {
    final ok = preflight.canJoin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _line(
          ok ? Icons.check_circle_outline : Icons.error_outline,
          ok ? AppTheme.successFg : AppTheme.dangerFg,
          ok
              ? l10n.d(
                  'Server bereikt — gasttoegang werkt en de vergadercomponent is gevonden.',
                )
              : failureText(l10n, preflight.failureReason!),
        ),
        if (preflight.diagnosticsDetail != null)
          _line(
            Icons.info_outline,
            AppTheme.slate600,
            preflight.diagnosticsDetail!,
          ),
        if (preflight.identityLabel != null)
          _line(
            Icons.badge_outlined,
            AppTheme.slate600,
            '${l10n.d('U verschijnt als')}: ${preflight.identityLabel}',
          ),
        _line(Icons.lock_outline, AppTheme.slate600, switch (preflight.e2ee) {
          MeetingE2eeStatus.on => l10n.d('Media is end-to-end versleuteld.'),
          MeetingE2eeStatus.off => l10n.d(
            'Media is niet end-to-end versleuteld (verloopt via de server).',
          ),
          MeetingE2eeStatus.unknown => l10n.d(
            'End-to-end-versleuteling van media is onbekend.',
          ),
        }),
        if (preflight.egressOrigins.isNotEmpty)
          _line(
            Icons.cloud_outlined,
            AppTheme.slate600,
            '${l10n.d('Verkeer gaat naar')}: '
            '${preflight.egressOrigins.join(', ')}',
          ),
      ],
    );
  }

  static String failureText(
    AppLocalizations l10n,
    MeetingFailureReason reason,
  ) => switch (reason) {
    MeetingFailureReason.accountRequired => l10n.d(
      'Deze server vraagt een account; anonieme gasten kunnen niet deelnemen.',
    ),
    MeetingFailureReason.guestDisabled => l10n.d(
      'Gasttoegang is uitgeschakeld op deze server.',
    ),
    MeetingFailureReason.appApprovalRequired => l10n.d(
      'Deze vergadering vereist goedkeuring van een beheerder.',
    ),
    MeetingFailureReason.meetingTypeUnsupported => l10n.d(
      'Deze server biedt geen vergadervorm die OciDeck ondersteunt.',
    ),
    MeetingFailureReason.providerUnavailable => l10n.d(
      'De server is niet bereikbaar of weigerde de verbinding.',
    ),
  };

  Widget _line(IconData icon, Color color, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 12, color: color)),
        ),
      ],
    ),
  );
}
