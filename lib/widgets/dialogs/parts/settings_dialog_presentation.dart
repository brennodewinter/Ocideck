// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (the style-profile tab); all imports live in
// the main library file. Instance methods relocate verbatim into an extension on
// _SettingsDialogState — same library, same members, no behaviour change.
part of '../settings_dialog.dart';

/// Voor welk vlak de instellingen in beeld staan.
///
/// Een stijlprofiel draagt drie soorten instellingen, en die liepen door
/// elkaar: het lettertype en de basiskleuren gelden overal, een titelbalk
/// bestaat alleen op een dia, en een koptekst alleen op een blad. Wie de
/// documentkant openzette kreeg tóch de dia-kleuren te zien, met een
/// schakelaar ("Logo: presentatie + document") die moest uitleggen wat waar
/// gold.
///
/// Vandaar deze drie: [general] is wat beide vlakken dragen, [document] en
/// [presentation] zijn wat alléén dáár bestaat. Een veld hoort in precies één
/// van de drie — dat is de hele regel, en het is aan de indeling te zien.
enum _StyleSurface {
  general(Icons.tune),
  document(Icons.description_outlined),
  presentation(Icons.slideshow_outlined);

  const _StyleSurface(this.icon);

  final IconData icon;

  String label(AppLocalizations l10n) => switch (this) {
    _StyleSurface.general => l10n.d('Algemeen'),
    _StyleSurface.document => l10n.d('Document'),
    _StyleSurface.presentation => l10n.d('Presentatie'),
  };

  /// De regel onder de keuzeknoppen: waar de instellingen hieronder landen.
  /// Zonder die regel moet de gebruiker het uit de veldnamen afleiden, en juist
  /// dat ging eerder mis.
  String hint(AppLocalizations l10n) => switch (this) {
    _StyleSurface.general => l10n.d('Geldt voor documenten en presentaties'),
    _StyleSurface.document => l10n.d('Alleen voor documenten'),
    _StyleSurface.presentation => l10n.d('Alleen voor presentaties'),
  };
}

extension _SettingsPresentationTab on _SettingsDialogState {
  Widget _presentationStyleTab(List<ThemeProfile> profiles) {
    final l10n = context.l10n;
    final styleBuilder = _DocumentStyleBuilder(this);
    final surface = styleBuilder._activeSurface(l10n);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        styleBuilder._styleProfileCards(profiles),
        const SizedBox(height: 18),
        _profileSelector(profiles),
        const SizedBox(height: 18),
        styleBuilder._surfaceSelector(l10n, surface),
        const SizedBox(height: 8),
        styleBuilder._surfaceHint(l10n, surface),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final editor = styleBuilder._surfaceEditor(l10n, surface);
            final preview = styleBuilder._surfacePreview(l10n, surface);
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
        const SizedBox(height: 24),
        // Cockpit is een specialisme, geen algemeen slidetype — de kleuren
        // horen bij de dia-stijl, maar staan ingeklapt zodat ze niet op het
        // hoofdpad liggen (#1957).
        AdvancedSection(
          title: l10n.d('Cockpit'),
          initiallyExpanded: false,
          children: [_cockpitTab()],
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
