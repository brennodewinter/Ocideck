// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (the presentation-style tab); all imports live in
// the main library file. Instance methods relocate verbatim into an extension on
// _SettingsDialogState — same library, same members, no behaviour change.
part of '../settings_dialog.dart';

extension _SettingsPresentationTab on _SettingsDialogState {
  Widget _presentationStyleTab(List<ThemeProfile> profiles) {
    final l10n = context.l10n;
    final styleBuilder = _DocumentStyleBuilder(this);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        styleBuilder._styleProfileCards(profiles),
        const SizedBox(height: 18),
        _profileSelector(profiles),
        const SizedBox(height: 18),
        styleBuilder._surfaceSelector(l10n),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final presentation = styleBuilder._showsPresentation(l10n);
            final editor = presentation
                ? styleBuilder._presentationStyleSettings(l10n)
                : styleBuilder._documentStyleSettings(l10n);
            final preview = presentation
                ? styleBuilder._presentationStylePreview(l10n)
                : styleBuilder._documentStylePreview(l10n);
            if (constraints.maxWidth < 820) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [editor, const SizedBox(height: 18), preview],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 350, child: editor),
                const SizedBox(width: 20),
                Expanded(child: preview),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _presentationStyleDivider(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Divider(height: 1),
        const SizedBox(height: 16),
        _sectionTitle(title),
      ],
    );
  }
}
