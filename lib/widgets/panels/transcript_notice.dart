// De meldingstrook van een transcriptdocument (#2511, contract §3.1/§3.4).
//
// Twee eerlijke meldingen, allebei herstelbaar — er verdwijnt nooit tekst:
//  * de marker is beschadigd of verplaatst: het bestand degradeert tot
//    gewoon document, de rauwe regels blijven zichtbaar, en deze strook
//    zegt waarom er geen transcript-weergave is;
//  * de `audio="…"`-verwijzing wijst naar een bestand dat er niet (meer)
//    ligt: het transcript blijft volledig bewerkbaar en de provenance leest
//    gewoon door; de strook meldt de missende bijlage, met een knop om
//    opnieuw te kijken voor wie het bestand terugzet.
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../services/transcription/transcript_audio_probe.dart';
import '../../services/transcription/transcript_marker.dart';
import '../../theme/app_theme.dart';

/// Waarschuwt bij een beschadigde transcript-marker of bij ontbrekende
/// audio. Rendeert niets voor een gewoon document, voor een gezond
/// transcript, en op plekken waar het bestaan van de audio niet te
/// verifiëren valt (web, of een nog-niet-opgeslagen document).
class TranscriptNotice extends StatefulWidget {
  const TranscriptNotice({
    super.key,
    required this.source,
    required this.projectPath,
  });

  /// De volledige documentsource — front matter inclusief.
  final String source;

  /// De werkmappen van het document (de map waar `media/` hoort te staan),
  /// of null voor een document dat nog geen pad heeft.
  final String? projectPath;

  @override
  State<TranscriptNotice> createState() => _TranscriptNoticeState();
}

class _TranscriptNoticeState extends State<TranscriptNotice> {
  /// `true` zodra de probe bevestigt dat het audiobestand ontbreekt. Tot
  /// die uitslag (of bij `null`, "niet te verifiëren") zwijgt de strook.
  bool _audioMissing = false;
  String? _probedFor;

  @override
  Widget build(BuildContext context) {
    final detection = detectTranscript(widget.source);
    return switch (detection) {
      MalformedTranscript(issues: final issues) => _strip(
        context,
        _issueText(context.l10n, issues.first.kind),
      ),
      ValidTranscript(marker: final marker) => _audioStrip(context, marker),
      NoTranscript() => const SizedBox.shrink(),
    };
  }

  /// De audio-check loopt pas als er een verwijzing ís, en wordt gecachet
  /// per (pad, project) — een stat per frame is precies waar de renderweg
  /// niet om vraagt.
  Widget _audioStrip(BuildContext context, TranscriptMarker marker) {
    final audio = marker.audioPath;
    if (audio == null) return const SizedBox.shrink();
    final key = '${widget.projectPath} $audio';
    if (_probedFor != key) {
      _probedFor = key;
      _audioMissing = transcriptAudioExists(widget.projectPath, audio) == false;
    }
    if (!_audioMissing) return const SizedBox.shrink();
    return _strip(
      context,
      context.l10n.d(
        'Het audiobestand is verplaatst of verwijderd. Het transcript blijft volledig beschikbaar.',
      ),
      action: IconButton(
        visualDensity: VisualDensity.compact,
        iconSize: 16,
        tooltip: context.l10n.d('Opnieuw controleren'),
        icon: const Icon(Icons.refresh),
        onPressed: () => setState(() {
          _audioMissing =
              transcriptAudioExists(widget.projectPath, audio) == false;
        }),
      ),
    );
  }

  Widget _strip(BuildContext context, String text, {Widget? action}) =>
      Material(
        // `warningBgSoft`/`warningFg` is het modus-bewuste paar: een tint van
        // de fg-kleur werkt niet — in donker is die fg licht en valt de strook
        // dan op de achtergrond door als bijna-wit vlak met witte tekst.
        color: AppTheme.warningBgSoft,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.iceBlue)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_outlined,
                size: 14,
                color: AppTheme.warningFg,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(fontSize: 12, color: AppTheme.warningFg),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ?action,
            ],
          ),
        ),
      );

  String _issueText(
    AppLocalizations l10n,
    TranscriptMarkerIssueKind kind,
  ) => switch (kind) {
    TranscriptMarkerIssueKind.misplaced => l10n.d(
      'De transcript-marker staat niet op de eerste regel; het document wordt als gewone tekst behandeld.',
    ),
    TranscriptMarkerIssueKind.duplicate => l10n.d(
      'Er staan meerdere transcript-markers in; het document wordt als gewone tekst behandeld.',
    ),
    TranscriptMarkerIssueKind.malformed => l10n.d(
      'De transcript-marker is beschadigd; het document wordt als gewone tekst behandeld.',
    ),
    TranscriptMarkerIssueKind.unsafeAudioPath => l10n.d(
      'De audioverwijzing in de transcript-marker wijst buiten de projectmap; het document wordt als gewone tekst behandeld.',
    ),
    TranscriptMarkerIssueKind.unsupportedVersion => l10n.d(
      'De transcript-marker is van een nieuwere versie; het document wordt als gewone tekst behandeld.',
    ),
  };
}
