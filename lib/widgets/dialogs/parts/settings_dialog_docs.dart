// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (the "Documentatie" pane); all imports live in the
// main library file. Instance methods relocate verbatim into an extension on
// _SettingsDialogState — same library, same members, no behaviour change.
part of '../settings_dialog.dart';

extension _SettingsDocs on _SettingsDialogState {
  /// Lists the bundled user documentation; each row opens the full-screen
  /// reader, and a search field filters the list by the words in each document.
  /// The licence also offers its canonical online version.
  ///
  /// Documents are grouped by audience so the list reads as named sections
  /// rather than one long flat run. Every group carries a heading (including the
  /// first), so no tile floats without a category. The `assetBase` string
  /// literals below are what docs_registration_test.dart greps for — keep them
  /// as literals here when adding a document.
  Widget _documentationTab() {
    final l10n = context.l10n;
    return DocumentationSearchTab(
      sections: [
        _userDocs(l10n),
        _technicalDocs(l10n),
        _licenceDocs(l10n),
        _designDocs(l10n),
      ],
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

DocSection _technicalDocs(AppLocalizations l10n) => DocSection(
  label: l10n.d('Techniek'),
  entries: [
    DocEntry(
      icon: Icons.account_tree_outlined,
      title: l10n.d('Architectuur'),
      assetBase: 'docs/ARCHITECTURE.md',
    ),
    DocEntry(
      icon: Icons.build_outlined,
      title: l10n.d('Bouwinstructies'),
      assetBase: 'docs/BUILD.md',
    ),
    DocEntry(
      icon: Icons.fact_check_outlined,
      title: l10n.d('Kwaliteitscontroles'),
      assetBase: 'docs/CHECKS.md',
    ),
    DocEntry(
      icon: Icons.map_outlined,
      title: l10n.d('Broncodekaart'),
      assetBase: 'docs/SOURCE_MAP.md',
    ),
    DocEntry(
      icon: Icons.api_outlined,
      title: l10n.d('API-documentatie'),
      assetBase: 'docs/API_DOCUMENTATION.md',
    ),
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
      icon: Icons.volunteer_activism_outlined,
      title: l10n.d('Bijdragen'),
      assetBase: 'docs/CONTRIBUTING_GUIDELINES.md',
    ),
    DocEntry(
      icon: Icons.terminal_outlined,
      title: l10n.d('Ontwikkelomgeving'),
      assetBase: 'docs/DEVELOPMENT_SETUP_GUIDE.md',
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

// Design documents (docs/design/**) are their own class: forward-looking
// specs rather than product/reference docs, so they sit under a separate
// heading.
DocSection _designDocs(AppLocalizations l10n) => DocSection(
  label: l10n.d('Ontwerp'),
  entries: [
    DocEntry(
      icon: Icons.privacy_tip_outlined,
      title: l10n.d('OciWacht (ontwerp)'),
      assetBase: 'docs/design/OCIWACHT.md',
    ),
    DocEntry(
      icon: Icons.gavel_outlined,
      title: l10n.d('Lexiconlicenties: wat er nog nagevraagd moet worden'),
      assetBase: 'docs/design/LEXICON_LICENTIENAVRAAG.md',
    ),
    DocEntry(
      icon: Icons.groups_outlined,
      title: l10n.d('Samenwerking (ontwerp)'),
      assetBase: 'docs/design/COLLABORATION.md',
    ),
    DocEntry(
      icon: Icons.video_call_outlined,
      title: l10n.d('Teams-gastclient (ontwerp)'),
      assetBase: 'docs/design/TEAMS_GUEST_CLIENT.md',
    ),
    DocEntry(
      icon: Icons.commit_outlined,
      title: l10n.d('Git-opslag (ontwerp)'),
      assetBase: 'docs/design/GIT_STORAGE.md',
    ),
    DocEntry(
      icon: Icons.fact_check_outlined,
      title: l10n.d('Nog te verifiëren'),
      assetBase: 'docs/design/VERIFICATION.md',
    ),
    DocEntry(
      icon: Icons.shield_outlined,
      title: l10n.d('Pentestrapportage (ontwerp)'),
      assetBase: 'docs/design/PENTEST_MIAUW.md',
    ),
    DocEntry(
      icon: Icons.smart_toy_outlined,
      title: l10n.d('AI-assistentie (ontwerp)'),
      assetBase: 'docs/design/AI_ASSIST.md',
    ),
    DocEntry(
      icon: Icons.account_tree_outlined,
      title: l10n.d('Agentisch bouwplan (ontwerp)'),
      assetBase: 'docs/design/AGENTIC_BUILD_PLAN.md',
    ),
    DocEntry(
      icon: Icons.trending_up_outlined,
      title: l10n.d('Procesverbetering (ontwerp)'),
      assetBase: 'docs/design/PROCESS_IMPROVEMENT.md',
    ),
    DocEntry(
      icon: Icons.outgoing_mail,
      title: l10n.d('Rapportagedistributie (ontwerp)'),
      assetBase: 'docs/design/OPENKAT_DISTRIBUTIE.md',
    ),
  ],
);
