// De opname-indicator uit #2510 (docs/design/TRANSCRIPTION.md §2.3).
//
// Zolang [recordingSessionProvider] een sessie heeft staat deze strook
// er — in de bannerkolom van de shell, dus boven élke tab en élke wissel
// daartussen. Hij toont welke bronnen meelopen, hoe lang al, en heeft de
// Stop altijd onder de vinger: zichtbaarheid is geen vlag maar een gevolg
// van de sessie zelf, en stoppen is een echte knop die dezelfde weg loopt
// als elke andere eindreden.
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/transcription/capture_source.dart';
import '../../state/transcription_provider.dart';
import '../../theme/app_theme.dart';

/// De zichtbare opnamestrook. Rendeert niets als er geen sessie is; de
/// shell mag hem daarom onvoorwaardelijk in de bannerkolom zetten.
class RecordingIndicator extends ConsumerStatefulWidget {
  const RecordingIndicator({super.key});

  @override
  ConsumerState<RecordingIndicator> createState() => _RecordingIndicatorState();
}

class _RecordingIndicatorState extends ConsumerState<RecordingIndicator> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // De duurteller is de enige reden dat deze strook een state is: de
    // sessie emiteert geen secondepuls, dus de klok bouwt zelf af en toe
    // opnieuw. Eén seconde is de zichtbare eenheid.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final handle = ref.watch(recordingSessionProvider);
    if (handle == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final running =
        '${l10n.d('Opname loopt')}: ${_sourceLabel(handle.kinds, l10n)}';
    final duration = _formatDuration(handle.elapsed);
    final caption = ref.watch(provisionalCaptionProvider);
    return Semantics(
      liveRegion: true,
      label: '$running, $duration',
      child: Material(
        color: AppTheme.dangerFg.withValues(alpha: 0.10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.iceBlue)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.fiber_manual_record,
                    size: 14,
                    color: AppTheme.dangerFg,
                  ),
                  const SizedBox(width: 8),
                  if (handle.kinds.contains(CaptureSourceKind.microphone))
                    _levelMark(ref.watch(micLevelProvider)),
                  Expanded(
                    child: Text(
                      '$running · $duration',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    // "Stop" alleen zegt een schermlezer niet wát er stopt.
                    label: l10n.d('Opname stoppen'),
                    child: ExcludeSemantics(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: AppTheme.dangerFg,
                        ),
                        icon: const Icon(Icons.stop_outlined, size: 16),
                        label: Text(l10n.d('Stoppen')),
                        onPressed: handle.stop,
                      ),
                    ),
                  ),
                ],
              ),
              if (caption.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${l10n.d('Voorlopige tekst')}: ${caption.text}',
                    style: const TextStyle(fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (caption.lagging)
                Text(
                  l10n.d('De tekst loopt achter. De opname zelf gaat door.'),
                  style: TextStyle(fontSize: 12, color: AppTheme.slate600),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// De bronlabel(s) voor de strook. `combinatie` is geen eigen naam maar de
/// twee kanalen die hij samenbrengt; meerdere bronnen in één sessie idem.
Widget _levelMark(double level) {
  return Padding(
    padding: const EdgeInsets.only(right: 8),
    child: SizedBox(
      width: 48,
      height: 6,
      child: LinearProgressIndicator(value: level.clamp(0, 1)),
    ),
  );
}

String _sourceLabel(Set<CaptureSourceKind> kinds, AppLocalizations l10n) {
  String label(CaptureSourceKind kind) => switch (kind) {
    CaptureSourceKind.file => l10n.d('Bestand'),
    CaptureSourceKind.microphone => l10n.d('Microfoon'),
    CaptureSourceKind.systemAudio => l10n.d('Systeemgeluid'),
    CaptureSourceKind.combination =>
      '${l10n.d('Microfoon')} + ${l10n.d('Systeemgeluid')}',
  };
  if (kinds.length == 1) return label(kinds.first);
  return kinds.map(label).join(' + ');
}

/// `m:ss`, of `h:mm:ss` zodra de opname een uur passeert — dezelfde vorm
/// als de proveniencetekst later schrijft (§3.1).
String _formatDuration(Duration d) {
  final total = d.inSeconds;
  String two(int v) => v.toString().padLeft(2, '0');
  final hours = total ~/ 3600;
  if (hours > 0) {
    return '$hours:${two((total % 3600) ~/ 60)}:${two(total % 60)}';
  }
  return '${total ~/ 60}:${two(total % 60)}';
}
