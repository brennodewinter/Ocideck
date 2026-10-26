// De live-server-opt-in voor de opnamedialogen (#2525, §4.3).
//
// De optie bestaat pas na een áantoonbare protocolproef: staat er geen
// live-endpoint in het profiel, is het profiel uit, of spreekt de server
// het `vosk-ws-1`-protocol niet, dan is er geen stille keuze maar een
// benoemde reden (of helemaal geen rij). De checkbox is de
// sessieconsent: hij noemt de host, welke bronnen live meegaan en wie
// het bewaarbeleid bepaalt — de Start-knop maakt er een
// `ServerConsent.liveSession` van.
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/asr_server_profile.dart';
import '../../services/transcription/asr_live_engine_factory.dart';
import '../../services/transcription/asr_server_engine.dart';
import '../../state/transcription_provider.dart';
import '../../theme/app_theme.dart';

/// De proef zoals de dialoog hem gebruikt — testhaak: widgettests
/// leveren een instantie met fake-transport, de app bouwt de echte.
typedef LiveProbeRunner =
    Future<AsrServerProbe> Function(AsrServerProfile profile);

/// De uitkomst van [LiveServerOptIn] voor de aanroepende knop: geen
/// live, of wel met de host die de consent moet benoemen.
class LiveOptInState {
  const LiveOptInState({this.chosen = false, this.host = ''});

  final bool chosen;
  final String host;
}

class LiveServerOptIn extends ConsumerStatefulWidget {
  const LiveServerOptIn({
    super.key,
    required this.sourcesLabel,
    required this.onChanged,
    this.probeRunner,
  });

  /// Welke bronnen live meegaan, in de taal van deze dialoog
  /// (`'microfoon'`, `'microfoon + systeemgeluid'`).
  final String sourcesLabel;

  /// Meldt elke wijziging van de keuze én de host aan de ouder — die
  /// bouwt de `ServerConsent.liveSession` pas bij Start.
  final void Function(LiveOptInState state) onChanged;

  final LiveProbeRunner? probeRunner;

  @override
  ConsumerState<LiveServerOptIn> createState() => _LiveServerOptInState();
}

class _LiveServerOptInState extends ConsumerState<LiveServerOptIn> {
  AsrServerProbe? _probe;
  var _probing = true;
  var _chosen = false;

  bool get _offered {
    // Op web leveren de huidige bronnen (web_media_source) geen
    // liveChunks — een aangevinkte optie zou daar stil niets doen, en
    // een dode keuze is erger dan geen keuze. De transporthelft staat
    // er wél: zodra een web-bron live-blokken levert kan deze poort weg.
    // ponytail: web-bronnen leveren nog geen liveChunks; upgrade-pad is
    // MediaRecorder→PCM-chunks in web_media_source, daarna deze regel uit.
    if (kIsWeb) return false;
    final profile = ref.read(asrServerProfileProvider);
    return profile.enabled && profile.hasLiveEndpoint;
  }

  @override
  void initState() {
    super.initState();
    if (_offered) unawaited(_probeLive());
  }

  Future<void> _probeLive() async {
    final profile = ref.read(asrServerProfileProvider);
    final runner =
        widget.probeRunner ?? ((p) => createAsrLiveServerEngine(p).probeLive());
    try {
      final probe = await runner(profile);
      if (mounted) {
        setState(() {
          _probe = probe;
          _probing = false;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _probe = const AsrServerProbe(
            status: AsrProbeStatus.unreachable,
            detail: 'probe faalde',
          );
          _probing = false;
        });
      }
    }
  }

  void _pick(bool value) {
    setState(() => _chosen = value);
    widget.onChanged(
      LiveOptInState(
        chosen: value,
        host: ref.read(asrServerProfileProvider).liveHost,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_offered) return const SizedBox.shrink();
    final l10n = context.l10n;
    final host = ref.watch(asrServerProfileProvider.select((p) => p.liveHost));
    final probe = _probe;
    if (_probing) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.d('Live-server wordt getest…'),
                style: TextStyle(fontSize: 12, color: AppTheme.slate600),
              ),
            ),
          ],
        ),
      );
    }
    if (probe == null || probe.status != AsrProbeStatus.reachable) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          '${l10n.d('Voorlopige tekst live via {host} is niet beschikbaar — de server is onbereikbaar of spreekt het live-protocol niet.').replaceAll('{host}', host)} (${probe?.detail ?? '?'})',
          style: TextStyle(fontSize: 12, color: AppTheme.amber700),
        ),
      );
    }
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        l10n.d('Voorlopige tekst live via {host}').replaceAll('{host}', host),
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        l10n
            .d(
              'Tijdens de opname gaat {bron} live naar deze server. De opname blijft volledig op dit apparaat; wat de server bewaart is zijn beleid.',
            )
            .replaceAll('{bron}', widget.sourcesLabel),
        style: const TextStyle(fontSize: 11.5),
      ),
      value: _chosen,
      onChanged: (v) => _pick(v ?? false),
    );
  }
}
