// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (the presentation-style tab); all imports live in
// the main library file. Instance methods relocate verbatim into an extension on
// _SettingsDialogState — same library, same members, no behaviour change.
part of '../settings_dialog.dart';

extension _SettingsPresentationTab on _SettingsDialogState {
  Widget _presentationStyleTab(List<ThemeProfile> profiles) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _profileScopeBanner(),
        _sectionTitle(l10n.t('styleProfile')),
        _profileSelector(profiles),
        const SizedBox(height: 20),
        _sectionTitle(l10n.d('Lettertype')),
        _fontSection(),
        _presentationStyleDivider(l10n.t('settingsColors')),
        ..._colorsSectionChildren(),
        _presentationStyleDivider(l10n.d('Animatie')),
        ..._animationSettings(),
        _presentationStyleDivider(l10n.d('Logo en footer')),
        ..._logoSectionChildren(),
        const SizedBox(height: 18),
        _stylePreview(),
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
