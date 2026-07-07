// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (the "Documentatie" pane); all imports live in the
// main library file. Instance methods relocate verbatim into an extension on
// _SettingsDialogState — same library, same members, no behaviour change.
part of '../settings_dialog.dart';

extension _SettingsDocs on _SettingsDialogState {
  /// Lists the bundled user documentation; each row opens the full-screen
  /// reader. The licence also offers its canonical online version.
  Widget _documentationTab() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _docTile(
          Icons.menu_book_outlined,
          l10n.d('Gebruikershandleiding'),
          assetBase: 'docs/USER_GUIDE.md',
        ),
        _docTile(
          Icons.keyboard_outlined,
          l10n.d('Sneltoetsen'),
          assetBase: 'docs/SHORTCUTS.md',
        ),
        _docTile(
          Icons.description_outlined,
          l10n.d('Bestandsformaat'),
          assetBase: 'docs/FILE_FORMAT.md',
        ),
        _docTile(
          Icons.account_tree_outlined,
          l10n.d('Architectuur'),
          assetBase: 'docs/ARCHITECTURE.md',
        ),
        _docTile(
          Icons.build_outlined,
          l10n.d('Bouwinstructies'),
          assetBase: 'docs/BUILD.md',
        ),
        _docTile(
          Icons.fact_check_outlined,
          l10n.d('Kwaliteitscontroles'),
          assetBase: 'docs/CHECKS.md',
        ),
        _docTile(
          Icons.map_outlined,
          l10n.d('Broncodekaart'),
          assetBase: 'docs/SOURCE_MAP.md',
        ),
        _docTile(
          Icons.balance_outlined,
          l10n.d('Licentienaleving'),
          assetBase: 'docs/LICENSE_COMPLIANCE.md',
        ),
        _docTile(
          Icons.inventory_2_outlined,
          l10n.d('Softwarestuklijst (SBOM)'),
          assetBase: 'docs/SBOM.md',
        ),
        _docTile(
          Icons.gavel_outlined,
          l10n.d('Licentie (EUPL 1.2)'),
          assetBase: 'LICENSE.md',
          onlineUrl: PrivacyStatementContent.licenseUrl,
        ),
        // Design documents (docs/design/**) are their own class: forward-looking
        // specs rather than product/reference docs, so they sit under a separate
        // heading. Guarded by docs_registration_test.dart.
        _docSectionHeader(l10n.d('Ontwerp')),
        _docTile(
          Icons.groups_outlined,
          l10n.d('Samenwerking (ontwerp)'),
          assetBase: 'docs/design/COLLABORATION.md',
        ),
      ],
    );
  }

  /// Small caps-style heading that separates a class of documents (e.g. the
  /// design specs) from the general documentation above it.
  Widget _docSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10, left: 2),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppTheme.slate400,
        ),
      ),
    );
  }

  Widget _docTile(
    IconData icon,
    String title, {
    required String assetBase,
    String? onlineUrl,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => DocumentReaderScreen.open(
            context,
            title: title,
            assetBase: assetBase,
            onlineUrl: onlineUrl,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.slate300),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(icon, size: 22, color: AppTheme.blue500),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slate700,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: AppTheme.slate400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
