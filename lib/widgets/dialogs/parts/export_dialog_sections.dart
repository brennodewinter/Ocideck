// Part of the export_dialog library — see ../export_dialog.dart.
//
// De keuzeknoppen en statusbalken vóór de formaatknoppen: hoeveel detail en
// voor wie deze export is, en de balk die zegt of alles klaar staat of dat er
// iets te melden valt.
//
// Afgesplitst toen `export_dialog.dart` weer tegen het plafond van 1000 regels
// liep (issue #514). Net als bij de meldingen: `build` en alles wat
// `setState` aanroept blijft in het hoofdbestand, deze extensie bevat alleen
// widget-opbouw die op bestaande state leest.
part of '../export_dialog.dart';

extension _ExportDialogSections on _ExportDialogState {
  // De knoppen zelf zijn eigen widgets. Een extensie telt mee voor het
  // klasseplafond, en deze dialoog zat daar al tegenaan.
  Widget _depthSelector() =>
      _DepthChoice(includeDetail: _includeDetail, onChanged: _selectDepth);

  Widget _questionSelector() =>
      _QuestionChoice(questions: _questions, onChanged: _selectQuestions);

  Widget _profileSelector() =>
      _AudienceChoice(profile: _profile, onChanged: _selectProfile);

  /// De balk boven de exportknoppen als er niets te melden valt.
  ///
  /// Groen zegt "wij hebben gekeken en niets gevonden". Staat de privacycontrole
  /// uit, dan is de tweede helft van die zin niet waar, en juist die helft leest
  /// de gebruiker als toestemming om te delen. Dan wordt de balk neutraal en
  /// zegt hij wát er niet is nagekeken — plus waar hij dat aanzet, want een
  /// melding zonder uitweg is een doodlopende straat met tekst.
  Widget _readyBanner(AppLocalizations l10n) {
    final checked = widget.privacyChecksEnabled;
    final foreground = checked ? AppTheme.successFg : AppTheme.slate600;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: checked ? AppTheme.successBg : AppTheme.slate100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: checked ? AppTheme.successBgSoft : AppTheme.slate300,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.task_alt, size: 16, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              checked
                  ? '${l10n.d('Klaar voor export')} — '
                        '${l10n.d('Geen kwaliteitsproblemen gevonden')}'
                  : '${l10n.d('Klaar voor export')} — '
                        '${l10n.d('Er is niet gekeken naar persoonsgegevens, bijzondere gegevens en geheimen: de privacycontrole staat uit bij Beveiliging.')}',
              style: TextStyle(fontSize: 11, color: foreground),
            ),
          ),
        ],
      ),
    );
  }

  Widget _qualityBanner(AppLocalizations l10n) {
    final result = widget.qualityResult;
    final hasErrors = result.errorCount > 0;
    final hasWarnings = result.warningCount > 0;
    final color = hasErrors
        ? AppTheme.dangerBg
        : hasWarnings
        ? AppTheme.warningBg
        : AppTheme.infoBg;
    final borderColor = hasErrors
        ? AppTheme.dangerBgSoft
        : hasWarnings
        ? AppTheme.warningBgSoft
        : AppTheme.userNotesBorder;
    final iconColor = hasErrors
        ? AppTheme.dangerFg
        : hasWarnings
        ? AppTheme.warningFg
        : AppTheme.slate600;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.accessibility_new_outlined,
                size: 16,
                color: iconColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${l10n.d('Slidekwaliteit')}: '
                  '${formatSlideQualityCountSummary(l10n, result)}',
                  style: TextStyle(fontSize: 11, color: iconColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  showSlideQualityDetailsDialog(context, result: result),
              icon: const Icon(Icons.list_alt_outlined, size: 14),
              label: Text(l10n.d('Bekijk meldingen…')),
              style: TextButton.styleFrom(
                foregroundColor: iconColor,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hoeveel detail wil deze lezer?
///
/// De derde as naast classificatie en redactie: TLP zegt wíé het mag zien,
/// redactie wélke gegevens eruit mogen, en dit hoevéél detail erbij hoort.
/// De keuze landt in de bestandsnaam (`…-beknopt.pdf`).
class _DepthChoice extends StatelessWidget {
  const _DepthChoice({required this.includeDetail, required this.onChanged});

  final bool includeDetail;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d('Hoeveel detail?'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: true,
                label: Text(l10n.d('Met verdieping')),
                icon: const Icon(Icons.unfold_more, size: 15),
              ),
              ButtonSegment(
                value: false,
                label: Text(l10n.d('Beknopt')),
                icon: const Icon(Icons.unfold_less, size: 15),
              ),
            ],
            selected: {includeDetail},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ],
      ),
    );
  }
}

/// Gaan de quizvragen mee, blijven ze weg, of is dit bestand alleen de vragen?
///
/// Los van diepgang: een hand-out voor de zaal is iets anders dan het
/// vragenblad voor de docent. De standaard laat de naam ongemoeid.
class _QuestionChoice extends StatelessWidget {
  const _QuestionChoice({required this.questions, required this.onChanged});

  final QuestionExport questions;
  final ValueChanged<QuestionExport> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hint = switch (questions) {
      QuestionExport.included => l10n.d(
        'De quizvragen gaan mee in dit bestand.',
      ),
      QuestionExport.omitted => l10n.d(
        'Dit bestand slaat de quizvragen over. De naam eindigt op -zonder-vragen.',
      ),
      QuestionExport.only => l10n.d(
        'Dit bestand bevat alleen de quizvragen. De naam eindigt op -vragen.',
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d('Quizvragen'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          SegmentedButton<QuestionExport>(
            segments: [
              ButtonSegment(
                value: QuestionExport.included,
                label: Text(l10n.d('Met vragen')),
                icon: const Icon(Icons.quiz_outlined, size: 15),
              ),
              ButtonSegment(
                value: QuestionExport.omitted,
                label: Text(l10n.d('Zonder vragen')),
                icon: const Icon(Icons.playlist_remove_outlined, size: 15),
              ),
              ButtonSegment(
                value: QuestionExport.only,
                label: Text(l10n.d('Alleen vragen')),
                icon: const Icon(Icons.fact_check_outlined, size: 15),
              ),
            ],
            selected: {questions},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) => onChanged(s.first),
          ),
          const SizedBox(height: 4),
          Text(hint, style: TextStyle(fontSize: 11, color: AppTheme.slate400)),
        ],
      ),
    );
  }
}

/// Voor wie is deze export?
///
/// Eén bron, twee versies. De opdrachtgever krijgt alles; de bredere kring
/// krijgt het geredigeerde exemplaar. Het profiel staat in de bestandsnaam.
class _AudienceChoice extends StatelessWidget {
  const _AudienceChoice({required this.profile, required this.onChanged});

  final PrivacyExportProfile profile;
  final ValueChanged<PrivacyExportProfile> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d('Voor wie is deze export?'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          SegmentedButton<PrivacyExportProfile>(
            segments: [
              ButtonSegment(
                value: PrivacyExportProfile.full,
                label: Text(l10n.d('Volledig')),
                icon: const Icon(Icons.lock_open_outlined, size: 15),
              ),
              ButtonSegment(
                value: PrivacyExportProfile.redacted,
                label: Text(l10n.d('Geredigeerd')),
                icon: const Icon(Icons.visibility_off_outlined, size: 15),
              ),
            ],
            selected: {profile},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) => onChanged(s.first),
          ),
          const SizedBox(height: 4),
          Text(
            profile == PrivacyExportProfile.full
                ? l10n.d(
                    'Voor de opdrachtgever of auditor: alleen wat je zelf op "weglaten" hebt gezet, gaat eruit. De rest blijft leesbaar, zodat een derde partij de bevindingen kan controleren.',
                  )
                : l10n.d(
                    'Voor de bredere kring: alles wat de controle vindt gaat eruit, ook op slides die je hebt geaccepteerd. Het bestand krijgt "-geredigeerd" in de naam.',
                  ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ],
      ),
    );
  }
}
