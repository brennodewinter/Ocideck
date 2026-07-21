import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/app_localizations.dart';
import 'reader/document_reader_screen.dart';

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
        _card(theme, _licenseCard(context, theme, l10n)),
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
        _card(theme, _egressCard(l10n)),
        const SizedBox(height: 16),

        // ── 4. The privacy check ─────────────────────────────────────────────
        //
        // De belofte moet hier kleiner zijn dan de feature aanvoelt. Wie denkt
        // dat de controle álles vindt, deelt op grond van die aanname — en dan
        // heeft een gemiste bevinding meer schade aangericht dan geen controle.
        // Vandaar dat de grens er in de verklaring net zo hard in staat als de
        // belofte.
        _heading(
          theme,
          Icons.privacy_tip_outlined,
          l10n.d('De privacycontrole'),
        ),
        _card(
          theme,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.d(
                  'OciDeck leest je dia\'s na op gegevens die privacygevoelig kunnen zijn: identificatienummers, contactgegevens, telefoonnummers, bankrekeningen, sleutels en wachtwoorden, en bijzondere persoonsgegevens. Dat gebeurt volledig op dit apparaat: er wordt niets verstuurd, en de gevonden waarde zelf komt in geen enkele melding te staan.',
                ),
                style: _bodyStyle,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.d(
                  'De controle garandeert niet dat alles wordt gevonden; ze verkleint de kans dat er persoonsgegevens onbedoeld uitlekken.',
                ),
                style: _bodyStyle,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.d(
                  'Tekst in afbeeldingen blijft buiten beeld, gelinkte bestanden worden niet geopend, en gegevens zonder herkenbaar patroon herkent geen enkele scanner. Een dia zonder meldingen is een dia waarin wíj niets hebben gevonden, niet een dia waarvan vaststaat dat er niets in staat. Wat je deelt, blijft jouw beslissing en jouw verantwoordelijkheid.',
                ),
                style: _bodyStyle,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── 5. Redaction ─────────────────────────────────────────────────────
        _heading(
          theme,
          Icons.visibility_off_outlined,
          l10n.d('Gegevens weglaten (redactie)'),
        ),
        _card(
          theme,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.d(
                  'Zet je tekst tussen dubbele blokhaken, zoals [[het adres]], dan laat OciDeck die weg uit alles wat je toont en exporteert. Op de dia, in de presentatie, in de PDF, de PowerPoint en de HTML verschijnen alleen blokken.',
                ),
                style: _bodyStyle,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.d(
                  'Weggelaten is écht weggelaten, niet afgedekt. De tekst zit niet als onzichtbare laag onder een zwart balkje in de PDF, niet in de sprekersnotities van de PowerPoint, en niet in de broncode van de HTML. Wie het bestand openmaakt, kan er niets uit terughalen.',
                ),
                style: _bodyStyle,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.d(
                  'Je eigen bestand verandert niet. De oorspronkelijke tekst blijft in je markdown staan; redactie geldt alleen voor wat je deelt. Zo houd je je eigen gegevens.',
                ),
                style: _bodyStyle,
              ),
            ],
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

  /// Wat het apparaat verlaat, en waardoor.
  ///
  /// De opslagsoorten staan hier als losse regels naast de opsomming, niet
  /// erin. Die opsomming is één string in dertig talen; er een backend bij
  /// zetten betekent hem dertig keer opnieuw laten vertalen, en precies die
  /// drempel is waarom S3 er nooit in kwam en git er jaren buiten bleef. Eén
  /// korte regel per opslagsoort maakt de volgende additief. Dát er een regel
  /// moet zijn, bewaakt `privacy_promise_test` tegen `StorageConnectionKind`.
  Widget _egressCard(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        l10n.d(
          'OciDeck verzamelt geen statistieken en stuurt uit zichzelf niets naar buiten. Standaard blijft alles op dit apparaat. Gegevens verlaten dit apparaat alleen als jij dat kiest:\n\n•  Nextcloud/WebDAV: verbind je met een server, dan worden je inlognaam en wachtwoord bewaard (het wachtwoord veilig in de sleutelbos van je systeem) en worden de presentaties die je opent of opslaat naar die server verstuurd.\n•  Openen via URL: OciDeck haalt het bestand op van het adres dat je invoert.\n•  Online media (staat standaard uit): indien ingeschakeld laadt OciDeck afbeeldingen en video\'s van de adressen in je dia\'s.\n•  Externe links (zoals de online licentie) openen in je browser.',
        ),
        style: _bodyStyle,
      ),
      Text(
        l10n.d(
          '•  S3-opslag: verbind je met een bucket, dan worden het endpoint, de bucketnaam en je toegangssleutel bewaard (de geheime sleutel veilig in de sleutelbos van je systeem) en worden de presentaties die je opent of opslaat naar die opslagdienst verstuurd.',
        ),
        style: _bodyStyle,
      ),
      Text(
        l10n.d(
          '•  Git-opslag: verbind je met een repository, dan wordt je toegangstoken bewaard (veilig in de sleutelbos van je systeem) en worden de presentaties die je opslaat als commits naar die server verstuurd. Een werkkopie van de repository blijft onversleuteld op dit apparaat staan.',
        ),
        style: _bodyStyle,
      ),
      // Drie bestemmingen die de gebruiker niet zelf aanwijst. Ze horen hier
      // juist daarom: de opsomming hierboven zegt "alleen als jij dat kiest",
      // en die zin blijft alleen waar zolang de uitzonderingen erbij staan.
      // De CVE-spiegel is een server van de uitgever, ENISA en MITRE zijn niet
      // instelbaar, en de terugval via de eigen origin op web gebeurt zonder
      // aparte vraag. Zie docs/PRIVACY.md en docs/HOSTING.md §4.
      Text(
        l10n.d(
          '•  CVE opzoeken (staat standaard uit): staat het aan, dan gaat je zoekterm naar de ingestelde CVE-spiegel en, als die niets vindt, naar de Europese database van ENISA en naar MITRE.',
        ),
        style: _bodyStyle,
      ),
      Text(
        l10n.d(
          '•  Een ingesloten YouTube- of Vimeo-video laadt de speler bij die dienst.',
        ),
        style: _bodyStyle,
      ),
      Text(
        l10n.d(
          '•  In de browser: weigert de browser een adres rechtstreeks op te halen, dan probeert OciDeck het via de server waar de app vandaan komt; dat adres komt dan bij die server terecht.',
        ),
        style: _bodyStyle,
      ),
      const SizedBox(height: 8),
      Text(
        l10n.d(
          'AI-assistentie (staat standaard uit): kies je een zelf-gehoste of cloud-backend, dan worden de teksten of afbeeldingen die je laat verwerken naar dat adres gestuurd. Wat je hebt geredigeerd, gaat er eerst uit. Een lokaal AI-model op dit apparaat verstuurt niets.',
        ),
        style: _bodyStyle,
      ),
    ],
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

  /// De licentiekaart: samenvatting, een knop naar de volledige (gerenderde)
  /// licentie in het leesscherm, en de link naar de officiële online versies.
  Widget _licenseCard(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d(
            'OciDeck wordt geleverd onder de European Union Public Licence v1.2. Door akkoord te gaan aanvaard je deze licentie. Je mag OciDeck gebruiken, kopiëren, aanpassen en verspreiden onder de voorwaarden van de EUPL 1.2.',
          ),
          style: _bodyStyle,
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => DocumentReaderScreen.open(
              context,
              title: l10n.d('Licentie (EUPL 1.2)'),
              assetBase: 'LICENSE.md',
              onlineUrl: licenseUrl,
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(0, 32),
            ),
            icon: const Icon(Icons.menu_book_outlined, size: 16),
            label: Text(l10n.d('Lees de volledige licentie')),
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
}
