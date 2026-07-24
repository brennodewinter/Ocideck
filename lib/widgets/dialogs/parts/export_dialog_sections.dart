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
  /// Hoeveel detail wil deze lezer?
  ///
  /// De derde as naast classificatie en redactie, en bewust een eigen keuze:
  /// TLP zegt wíé het mag zien, redactie wélke gegevens eruit mogen, en dit
  /// hoevéél detail erbij hoort. Een slide kan prima openbaar zijn en tóch meer
  /// zijn dan waarvoor een managementpubliek kwam.
  ///
  /// Net als het profiel landt de keuze in de bestandsnaam (`…-beknopt.pdf`),
  /// om dezelfde reden: een verwisseling moet je kunnen zien.
  Widget _depthSelector(AppLocalizations l10n) {
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
            selected: {_includeDetail},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) => _selectDepth(s.first),
          ),
        ],
      ),
    );
  }

  /// Voor wie is deze export?
  ///
  /// Eén bron, twee versies. Dat is de kern van het pentestrapport-scenario: de
  /// opdrachtgever moet de bevinding kúnnen natrekken, dus die krijgt alles; de
  /// bredere kring krijgt hetzelfde rapport met de persoonsgegevens eruit.
  ///
  /// Het profiel staat in de bestandsnaam (`…-geredigeerd.pdf`). Dat is niet
  /// cosmetisch: de duurste fout die je met deze feature kunt maken, is het
  /// volledige exemplaar naar de brede kring sturen. Een verwisseling moet je
  /// kunnen *zien*, niet hoeven onthouden.
  Widget _profileSelector(AppLocalizations l10n) {
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
            selected: {_profile},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) => _selectProfile(s.first),
          ),
          const SizedBox(height: 4),
          Text(
            _profile == PrivacyExportProfile.full
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
