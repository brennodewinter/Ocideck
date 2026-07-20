// Part of the settings_dialog library — see ../settings_dialog.dart.
// Het overzicht van de gebundelde referentiestandaarden: wat we meedragen en
// welke versie dat is. Eigen bestand omdat de "Over"-pagina anders te lang
// wordt; de gegevens komen uit lib/services/reference_standards.dart.
part of '../settings_dialog.dart';

extension _SettingsStandards on _SettingsDialogState {
  /// Toont per standaard de versie die dit exemplaar van OciDeck meedraagt.
  ///
  /// Dit is de leeskant van hetzelfde register dat
  /// `tool/check_reference_data.dart` tegen upstream houdt. Bewust géén
  /// live-controle vanuit de app: dat zou een netwerkverbinding maken op een
  /// scherm waar niemand daarom vraagt, en OciDeck legt geen verkeer aan dat de
  /// gebruiker niet heeft gevraagd. De vergelijking met upstream hoort in de
  /// poort, hier staat wat je in handen hebt.
  Widget _standardsSection(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // "Standaarden" alleen zou de lading niet dekken: MIAUW is een methodiek,
      // geen standaard, en het lijstje hieronder mengt de twee bewust.
      _aboutHeading(
        Icons.menu_book_outlined,
        l10n.d('Standaarden en methodieken'),
      ),
      _aboutCard(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              // Eén literal, niet aaneengeplakt: de l10n-extractor leest
              // aangrenzende fragmenten als losse sleutels.
              // ignore: lines_longer_than_80_chars
              l10n.d(
                'De versies die in dit exemplaar zitten. Een pentestrapport hoort te vermelden waartegen is getoetst — en welke versie dat was.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            const SizedBox(height: 12),
            for (final standard in referenceStandards)
              _standardRow(l10n, standard),
          ],
        ),
      ),
    ],
  );

  Widget _standardRow(AppLocalizations l10n, ReferenceStandard standard) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    standard.name,
                    style: _SettingsAbout._aboutLabelStyle,
                  ),
                ),
                Text(
                  standard.bundledVersion.isEmpty
                      ? l10n.d('geen versienummer')
                      : standard.bundledVersion,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              standard.bundled,
              style: TextStyle(fontSize: 11.5, color: AppTheme.slate600),
            ),
            Row(
              children: [
                // Expanded, geen Spacer: "Specificatie van FIRST.Org —
                // attributie" is langer dan de kaart breed is, en een licentie
                // hoort af te breken in plaats van buiten beeld te vallen.
                Expanded(
                  child: Text(
                    standard.licence,
                    style: TextStyle(fontSize: 11, color: AppTheme.slate400),
                  ),
                ),
                _aboutLink(l10n.d('Bron'), standard.url),
              ],
            ),
          ],
        ),
      );
}
