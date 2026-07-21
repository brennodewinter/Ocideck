// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (the "Over OciDeck" pane); all imports live in
// the main library file. Instance methods relocate verbatim into an extension
// on _SettingsDialogState — same library, same members, no behaviour change.
part of '../settings_dialog.dart';

/// One of Brenno's ocicats that serves as a project mascot. Name and project
/// are proper nouns (kept verbatim across languages); [description] is the one
/// translated line.
class _CatMascot {
  final String asset;
  final String name;
  final String description;

  const _CatMascot(this.asset, this.name, this.description);
}

extension _SettingsAbout on _SettingsDialogState {
  Widget _aboutTab() {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _aboutBanner(l10n),
        const SizedBox(height: 22),

        // ── Origin: the Pilot Informatieautonomie ────────────────────────────
        _aboutOrigin(l10n),
        const SizedBox(height: 18),

        // ── Where the name comes from ────────────────────────────────────────
        _aboutHeading(
          Icons.badge_outlined,
          l10n.d('Waar komt de naam vandaan?'),
        ),
        _aboutCard(
          Text(
            l10n.d(
              '"Oci" verwijst naar de ocicat, het kattenras van de katten van Brenno de Winter. "Deck" is het Engelse woord voor een diaset. OciDeck maakt van eenvoudige tekst een verzorgde presentatie.',
            ),
            style: _aboutBodyStyle,
          ),
        ),
        const SizedBox(height: 18),

        // ── Publisher: Stichting LibreKAT ────────────────────────────────────
        _aboutHeading(
          Icons.volunteer_activism_outlined,
          l10n.d('Uitgever: Stichting LibreKAT'),
        ),
        _aboutCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/librekat-logo.png',
                      width: 44,
                      height: 44,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.d(
                        'OciDeck wordt uitgegeven door Stichting LibreKAT. De stichting werkt aan een veiligere digitale samenleving via open, controleerbare informatiebeveiliging, met de nadruk op kennisdeling, community-vorming en het ondersteunen van opensource-oplossingen.',
                      ),
                      style: _aboutBodyStyle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                l10n.d(
                  'De stichting is op 23 oktober 2025 bij notariële akte opgericht te Leeuwarden en heeft haar statutaire zetel in Noordwijk.',
                ),
                style: _aboutBodyStyle,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.d(
                  'Doelstellingen van de stichting:\n\n•  Opensource-software en -hardware voor veilige digitale infrastructuren stimuleren.\n•  Transparantie en reproduceerbaarheid in beveiligingsprocessen bevorderen.\n•  Onderzoek, trainingen en activiteiten rond digitale weerbaarheid organiseren.\n•  Burgers, bedrijven, overheid en maatschappelijke organisaties met elkaar verbinden.',
                ),
                style: _aboutBodyStyle,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.d(
                  'Kernwaarden: veiligheid, vrijheid en openheid, soevereiniteit, integriteit, kennisdeling, betrouwbaarheid, menselijkheid, luisteren en verbinden, "just culture" en duurzaamheid.',
                ),
                style: _aboutBodyStyle,
              ),
              const SizedBox(height: 12),
              Text(l10n.d('Bestuur'), style: _aboutLabelStyle),
              const SizedBox(height: 4),
              Text(
                l10n.d(
                  'Brenno de Winter (voorzitter), Jan Klopper (secretaris) en Astrid Oosenbrug (penningmeester).',
                ),
                style: _aboutBodyStyle,
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: _aboutLink(
                  l10n.d('Website van de stichting'),
                  'https://librekat.nl/',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // ── Contact details ──────────────────────────────────────────────────
        _standardsSection(l10n),
        const SizedBox(height: 18),

        _aboutHeading(Icons.contact_mail_outlined, l10n.d('Contact')),
        _aboutCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.d('Stichting LibreKAT'), style: _aboutLabelStyle),
              const SizedBox(height: 8),
              _aboutKeyValue(
                l10n.d('Adressen'),
                'Weidemolen 12, 2211 PW Noordwijkerhout\nWilhelminaplein 12, 8911 BS Leeuwarden',
              ),
              _aboutKeyValue(l10n.d('Telefoon'), '+31 85 333 2942'),
              _aboutKeyValue(
                l10n.d('E-mail'),
                'stichting@librekat.nl',
                linkUrl: 'stichting@librekat.nl',
              ),
              _aboutKeyValue('KvK', '98657836'),
              _aboutKeyValue('IBAN', 'NL63 TRIO 0321 2051 89'),
              _aboutKeyValue('BIC', 'TRIONL2U'),
              // Keyed, not d('Bank'): the source word "Bank" collides with the
              // cockpit artificial-horizon roll angle, which is translated as
              // aviation "bank" (Roulis/Rollen/…). This is the financial bank.
              _aboutKeyValue(l10n.t('bankLabel'), 'Triodos N.V.'),
            ],
          ),
        ),
        const SizedBox(height: 18),

        _aboutCatsSection(l10n),
      ],
    );
  }

  /// Heading, intro line and one card per mascot cat.
  Widget _aboutCatsSection(AppLocalizations l10n) {
    final cats = [
      _CatMascot(
        'assets/images/cat-branie.jpg',
        'Branie',
        l10n.d('Mascotte van de checklisttool.'),
      ),
      _CatMascot(
        'assets/images/cat-keiko.jpg',
        'Keiko',
        l10n.d('Mascotte van OpenKAT.'),
      ),
      _CatMascot(
        'assets/images/cat-otis.jpg',
        'Otis',
        l10n.d('Mascotte van MIAUW.'),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _aboutHeading(Icons.pets_outlined, l10n.d('De katten van Brenno')),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            l10n.d(
              'De mascottes van OciDeck en verwante projecten zijn de ocicats van Brenno de Winter.',
            ),
            style: _aboutBodyStyle,
          ),
        ),
        for (final cat in cats) ...[_catCard(cat), const SizedBox(height: 10)],
      ],
    );
  }

  static const _aboutBodyStyle = TextStyle(fontSize: 12, height: 1.45);
  static TextStyle get _aboutLabelStyle => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppTheme.slate700,
  );

  /// Branded header banner with the logo, app name and a one-line tagline.
  Widget _aboutBanner(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.navySoft, AppTheme.navy],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/images/ocideck-logo-eu.png',
            width: 48,
            height: 48,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.d('OciDeck'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.d(
                    'Verzorgde presentaties uit eenvoudige tekst — vrij, controleerbaar en met je gegevens op je eigen apparaat.',
                  ),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Where the project came from. The pilot is a proper noun and its domain a
  /// bare URL, so both stay out of the translated line.
  Widget _aboutOrigin(AppLocalizations l10n) => _aboutCard(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Dit project is bijvangst van de Pilot Informatieautonomie.'),
          style: _aboutBodyStyle,
        ),
        _aboutLink(
          'www.pilotinformatieautonomie.nl',
          'https://www.pilotinformatieautonomie.nl',
        ),
      ],
    ),
  );

  Widget _aboutHeading(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.blue500),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Widget _aboutCard(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppTheme.slate300),
      borderRadius: BorderRadius.circular(10),
    ),
    child: child,
  );

  Widget _aboutLink(String label, String url) => TextButton.icon(
    onPressed: () => openExternalUrl(url),
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      minimumSize: const Size(0, 32),
    ),
    icon: const Icon(Icons.open_in_new, size: 15),
    label: Text(label),
  );

  Widget _aboutKeyValue(String label, String value, {String? linkUrl}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.slate500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: linkUrl == null
                ? SelectableText(value, style: _aboutBodyStyle)
                : InkWell(
                    onTap: () => openExternalUrl(linkUrl),
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: AppTheme.blue500,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _catCard(_CatMascot cat) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.slate300),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      // IntrinsicHeight bounds the Row's cross axis so the stretched image can
      // fill the card height (which grows with the text) instead of being
      // asked for an infinite height inside the scroll view.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _catPhoto(cat),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cat.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slate700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(cat.description, style: _aboutBodyStyle),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The card's photo, clickable: a 116px sliver cropped to the card height
  /// shows little of the cat, so a tap opens the picture full-size in the same
  /// zoom viewer the question slides use.
  Widget _catPhoto(_CatMascot cat) {
    final label = context.l10n.d('Bekijk de foto op ware grootte');
    return Tooltip(
      message: label,
      child: SizedBox(
        width: 116,
        child: Semantics(
          button: true,
          label: '${cat.name} — $label',
          child: InkWell(
            onTap: () => showImageProviderZoomDialog(
              context,
              image: AssetImage(cat.asset),
              caption: cat.name,
            ),
            child: Image.asset(
              cat.asset,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    );
  }
}
