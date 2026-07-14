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
        DocSection(
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
          ],
        ),
        DocSection(
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
          ],
        ),
        DocSection(
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
        ),
        // Design documents (docs/design/**) are their own class: forward-looking
        // specs rather than product/reference docs, so they sit under a separate
        // heading.
        DocSection(
          label: l10n.d('Ontwerp'),
          entries: [
            DocEntry(
              icon: Icons.privacy_tip_outlined,
              title: l10n.d('Privacy Shield (ontwerp)'),
              assetBase: 'docs/design/PRIVACY_SHIELD.md',
            ),
            DocEntry(
              icon: Icons.groups_outlined,
              title: l10n.d('Samenwerking (ontwerp)'),
              assetBase: 'docs/design/COLLABORATION.md',
            ),
            DocEntry(
              icon: Icons.commit_outlined,
              title: l10n.d('Git-opslag (ontwerp)'),
              assetBase: 'docs/design/GIT_STORAGE.md',
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
          ],
        ),
      ],
    );
  }
}
