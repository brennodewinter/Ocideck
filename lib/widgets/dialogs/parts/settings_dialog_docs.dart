// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (the "Documentatie" pane); all imports live in the
// main library file. Instance methods relocate verbatim into an extension on
// _SettingsDialogState — same library, same members, no behaviour change.
part of '../settings_dialog.dart';

/// The repository where the *full* documentation lives — including the
/// developer-internal and forward-looking design docs that are deliberately not
/// bundled with the app (see the curated asset list in pubspec.yaml). The reader
/// links here so "the rest is on the repository" is one tap away, rather than
/// shipping every doc inside every build. The `/docs` folder is the landing
/// point; from there the whole tree is browsable.
const String kRepositoryDocsUrl =
    'https://pawprint.vigilis.online/LibreKAT/Ocideck/src/branch/main/docs';

extension _SettingsDocs on _SettingsDialogState {
  /// Lists the bundled documentation; each row opens the full-screen reader, and
  /// a search field filters the list by the words in each document. The licence
  /// also offers its canonical online version, and a footer links to the
  /// repository for the docs that are not bundled.
  ///
  /// Documents are grouped by audience so the list reads as named sections
  /// rather than one long flat run. Every group carries a heading (including the
  /// first), so no tile floats without a category. The `assetBase` string
  /// literals below are what docs_registration_test.dart greps for — keep them
  /// as literals here when adding a document, and mirror the keep/repo split in
  /// that test and in pubspec.yaml.
  Widget _documentationTab() {
    final l10n = context.l10n;
    return DocumentationSearchTab(
      sections: [
        _userDocs(l10n),
        _technicalDocs(l10n),
        _licenceDocs(l10n),
        _projectDocs(l10n),
      ],
      repositoryDocsUrl: kRepositoryDocsUrl,
    );
  }
}

// De vier catalogussecties zijn zuivere gegevens: ze lezen alleen l10n en
// raken geen enkele veld van _SettingsDialogState. Als extensiemethoden telden
// ze wel mee voor het klasseplafond van die state — 192 regels die daar niets
// te zoeken hebben. Los, op topniveau in ditzelfde part-bestand, zijn het
// dezelfde literals op dezelfde plek (docs_registration_test grept hierop)
// zonder de klasse te laten groeien.

DocSection _userDocs(AppLocalizations l10n) => DocSection(
  label: l10n.d('Gebruiker'),
  entries: [
    DocEntry(
      icon: Icons.menu_book_outlined,
      title: l10n.d('Gebruikershandleiding'),
      assetBase: 'docs/USER_GUIDE.md',
    ),
    DocEntry(
      icon: Icons.keyboard_outlined,
      title: l10n.d('Sneltoetsen'),
      assetBase: 'docs/SHORTCUTS.md',
    ),
    DocEntry(
      icon: Icons.description_outlined,
      title: l10n.d('Bestandsformaat'),
      assetBase: 'docs/FILE_FORMAT.md',
    ),
    DocEntry(
      icon: Icons.list_alt_outlined,
      title: l10n.d('Overzicht'),
      assetBase: 'docs/README.md',
    ),
    DocEntry(
      icon: Icons.help_outline,
      title: l10n.d('Veelgestelde vragen'),
      assetBase: 'docs/FAQ.md',
    ),
    DocEntry(
      icon: Icons.build_circle_outlined,
      title: l10n.d('Probleemoplossing'),
      assetBase: 'docs/TROUBLESHOOTING_GUIDE.md',
    ),
    DocEntry(
      icon: Icons.lock_outline,
      title: l10n.d('Privacy'),
      assetBase: 'docs/PRIVACY.md',
    ),
    DocEntry(
      icon: Icons.accessibility_new_outlined,
      title: l10n.d('Toegankelijkheid'),
      assetBase: 'docs/ACCESSIBILITY.md',
    ),
    DocEntry(
      icon: Icons.report_problem_outlined,
      title: l10n.d('Bekende beperkingen'),
      assetBase: 'docs/KNOWN_LIMITATIONS.md',
    ),
    DocEntry(
      icon: Icons.menu_book_outlined,
      title: l10n.d('Begrippenlijst'),
      assetBase: 'docs/GLOSSARY.md',
    ),
  ],
);

// Only the technical docs that bear on *using and running* OciDeck are bundled:
// performance (what limits a big deck hits), the security design (what the app
// does and does not do with your content), hosting (serving the web build), and
// migration (opening older decks). The developer-internal docs — architecture,
// build, checks, source map, API, contributing, dev setup — are not shipped in
// the app; they live in the repository and the footer links there. Moving one of
// these across the line means updating pubspec.yaml and docs_registration_test.
DocSection _technicalDocs(AppLocalizations l10n) => DocSection(
  label: l10n.d('Techniek'),
  entries: [
    DocEntry(
      icon: Icons.speed_outlined,
      title: l10n.d('Prestaties'),
      assetBase: 'docs/PERFORMANCE_GUIDE.md',
    ),
    DocEntry(
      icon: Icons.security_outlined,
      title: l10n.d('Beveiligingsontwerp'),
      assetBase: 'docs/SECURITY_DESIGN.md',
    ),
    DocEntry(
      icon: Icons.cloud_outlined,
      title: l10n.d('Hosting en uitrol'),
      assetBase: 'docs/HOSTING.md',
    ),
    DocEntry(
      icon: Icons.swap_horiz_outlined,
      title: l10n.d('Migratiegids'),
      assetBase: 'docs/MIGRATION_GUIDE.md',
    ),
  ],
);

DocSection _licenceDocs(AppLocalizations l10n) => DocSection(
  label: l10n.d('Licentie en naleving'),
  entries: [
    DocEntry(
      icon: Icons.balance_outlined,
      title: l10n.d('Licentienaleving'),
      assetBase: 'docs/LICENSE_COMPLIANCE.md',
    ),
    DocEntry(
      icon: Icons.inventory_2_outlined,
      title: l10n.d('Softwarestuklijst (SBOM)'),
      assetBase: 'docs/SBOM.md',
    ),
    DocEntry(
      icon: Icons.gavel_outlined,
      title: l10n.d('Licentie (EUPL 1.2)'),
      assetBase: 'LICENSE.md',
      onlineUrl: PrivacyStatementContent.licenseUrl,
    ),
  ],
);

// Het dankwoord hoort ook in deze lijst en niet alleen achter het hartje in de
// banner van "Over OciDeck": wie de namen zoekt, zoekt ze in de
// documentatielijst — en één klein icoon zonder woord erbij is geen vindplaats.
// Eigen sectie, want het is geen handleiding, geen techniek en geen licentie.
DocSection _projectDocs(AppLocalizations l10n) => DocSection(
  label: l10n.d('Over OciDeck'),
  entries: [
    DocEntry(
      icon: Icons.favorite_outline,
      title: l10n.d('Met dank aan'),
      assetBase: 'CONTRIBUTORS.md',
    ),
  ],
);
