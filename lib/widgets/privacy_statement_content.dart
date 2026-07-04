import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Shared licence + privacy copy for the consent gate and the settings screen,
/// so both stay in sync and truthful. Covers three things: the EUPL 1.2 licence
/// (with the full text available in-app), what OciDeck stores on this device,
/// and what leaves the device and when.
class PrivacyStatementContent extends StatelessWidget {
  const PrivacyStatementContent({super.key});

  static const licenseUrl =
      'https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12';

  static String? _fullLicense;

  static const _bodyStyle = TextStyle(fontSize: 12, height: 1.4);

  /// Testhaak: gooi de licentie-memo weg. Nodig omdat een widgettest de
  /// future in zijn (fake-async) zone kan starten; die completeert daarna
  /// nooit meer en zou elke latere lezer laten hangen.
  @visibleForTesting
  static void resetLicenseCacheForTest() {
    _fullLicense = null;
    // Ook de rootBundle-cache: die memoïseert dezelfde load en is dan met
    // dezelfde dode zone-future vergiftigd.
    rootBundle.evict('LICENSE.md');
  }

  /// The full EUPL 1.2 text, loaded once from the bundled `LICENSE.md` with its
  /// leading SPDX/HTML-comment header stripped. Cache het résultaat, niet de
  /// Future: een Future die in een test-/FakeAsync-zone ontstond en daar nooit
  /// voltooide bleef anders voorgoed gecachet en liet elke volgende lezer
  /// hangen (volgorde-afhankelijke testflake); een load die niets opleverde
  /// mag gewoon opnieuw.
  static Future<String> loadFullLicense() async {
    final cached = _fullLicense;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString('LICENSE.md');
    final end = raw.indexOf('-->');
    final body = end >= 0 ? raw.substring(end + 3) : raw;
    return _fullLicense = body.trim();
  }

  static Future<void> launchLicenseOnline() async {
    final uri = Uri.parse(licenseUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d(
            'OciDeck is vrije software onder de EUPL 1.2-licentie. Voordat je begint, vragen we je de licentie te accepteren. Hieronder lees je ook welke gegevens OciDeck op dit apparaat bewaart en wanneer er iets je apparaat verlaat.',
          ),
          style: _bodyStyle,
        ),
        const SizedBox(height: 18),

        // ── 1. Licence ───────────────────────────────────────────────────────
        _heading(theme, Icons.gavel_outlined, l10n.d('Licentie (EUPL 1.2)')),
        _card(theme, _licenseCard(theme, l10n)),
        const SizedBox(height: 16),

        // ── 2. What OciDeck stores on this device ────────────────────────────
        _heading(
          theme,
          Icons.save_outlined,
          l10n.d('Wat OciDeck op dit apparaat bewaart'),
        ),
        _card(
          theme,
          Text(
            l10n.d(
              'Om te werken en je werk niet te verliezen, bewaart OciDeck gegevens lokaal op dit apparaat:\n\n•  Je instellingen en voorkeuren (taal, mappen, stijl- en weergaveprofielen, recente bestanden).\n•  Je presentatiematerialen: de presentaties die je opslaat, automatische herstelkopieën en bijlagen zoals afbeeldingsbeschrijvingen.\n•  Deze toestemmingskeuze.\n\nJe kunt dit verwijderen door de bestanden te wissen of de instellingen te resetten.',
            ),
            style: _bodyStyle,
          ),
        ),
        const SizedBox(height: 16),

        // ── 3. What leaves the device ────────────────────────────────────────
        _heading(
          theme,
          Icons.cloud_upload_outlined,
          l10n.d('Wat je apparaat verlaat'),
        ),
        _card(
          theme,
          Text(
            l10n.d(
              'OciDeck verzamelt geen statistieken en stuurt uit zichzelf niets naar buiten. Standaard blijft alles op dit apparaat. Gegevens verlaten dit apparaat alleen als jij dat kiest:\n\n•  Nextcloud/WebDAV: verbind je met een server, dan worden je inlognaam en wachtwoord bewaard (het wachtwoord veilig in de sleutelbos van je systeem) en worden de presentaties die je opent of opslaat naar die server verstuurd.\n•  Openen via URL: OciDeck haalt het bestand op van het adres dat je invoert.\n•  Online media (staat standaard uit): indien ingeschakeld laadt OciDeck afbeeldingen en video\'s van de adressen in je dia\'s.\n•  Externe links (zoals de online licentie) openen in je browser.',
            ),
            style: _bodyStyle,
          ),
        ),
      ],
    );
  }

  Widget _card(ThemeData theme, Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: theme.colorScheme.surface,
      border: Border.all(color: theme.colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(8),
    ),
    child: child,
  );

  Widget _heading(ThemeData theme, IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  /// De licentiekaart: samenvatting, inklapbare volledige tekst en de link
  /// naar de officiële online versies.
  Widget _licenseCard(ThemeData theme, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d(
            'OciDeck wordt geleverd onder de European Union Public Licence v1.2. Door akkoord te gaan aanvaard je deze licentie. Je mag OciDeck gebruiken, kopiëren, aanpassen en verspreiden onder de voorwaarden van de EUPL 1.2.',
          ),
          style: _bodyStyle,
        ),
        // The card around this content has a background colour; an
        // ExpansionTile paints its ink on the nearest Material, so give it
        // a transparent one to avoid the debug "invisible ink" assertion.
        Material(
          type: MaterialType.transparency,
          child: Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                l10n.d('Lees de volledige licentie'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: [_fullLicenseViewer(theme), const SizedBox(height: 8)],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: launchLicenseOnline,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(0, 32),
            ),
            icon: const Icon(Icons.open_in_new, size: 15),
            label: Text(
              l10n.d('Volledige licentie online (23 officiële taalversies)'),
            ),
          ),
        ),
      ],
    );
  }

  /// Scrollbaar vak met de volledige, gebundelde licentietekst.
  Widget _fullLicenseViewer(ThemeData theme) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: FutureBuilder<String>(
        future: loadFullLicense(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const SizedBox(
              height: 40,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return SingleChildScrollView(
            child: SelectableText(
              snap.data!,
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.35,
                color: AppTheme.slate600,
              ),
            ),
          );
        },
      ),
    );
  }
}
