import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_models.dart';
import '../../theme/app_theme.dart';
import 'ociserve_account_avatar.dart';

/// Welke sectie van de leeromgeving-dialoog actief is.
enum OciServeCoursesSection {
  courses,
  progress,
  data,
  evidence,
  bookings,
  offerings,
}

/// De kopteksten van elke sectie, zodat zowel de zijbalk als de header van de
/// dialoog dezelfde naamgeving gebruiken zonder de sectie-state te kennen.
extension OciServeCoursesSectionCopy on OciServeCoursesSection {
  /// De kleine label-regel boven de kop.
  String eyebrow(AppLocalizations l10n) => switch (this) {
    OciServeCoursesSection.data => l10n.d('Privacy-inzage'),
    OciServeCoursesSection.evidence => l10n.d('Mijn bewijs'),
    OciServeCoursesSection.progress => l10n.d('Persoonlijk overzicht'),
    OciServeCoursesSection.bookings => l10n.d('Mijn inschrijvingen'),
    OciServeCoursesSection.offerings => l10n.d('Aanbod'),
    OciServeCoursesSection.courses => l10n.d('Mijn leeromgeving'),
  };

  /// De grote kop. [name] is de weergavenaam van de cursist en wordt alleen
  /// voor de cursussectie gebruikt.
  String title(AppLocalizations l10n, {String name = ''}) => switch (this) {
    OciServeCoursesSection.data => l10n.d('Mijn gegevens'),
    OciServeCoursesSection.evidence => l10n.d('Mijn bewijs'),
    OciServeCoursesSection.progress => l10n.d('Mijn voortgang'),
    OciServeCoursesSection.bookings => l10n.d('Mijn inschrijvingen'),
    OciServeCoursesSection.offerings => l10n.d('Aanbod'),
    OciServeCoursesSection.courses =>
      name.isEmpty
          ? l10n.d('Mijn cursussen')
          : l10n.d('Welkom, {naam}').replaceAll('{naam}', name),
  };

  /// De toelichting onder de kop.
  String subtitle(AppLocalizations l10n) => switch (this) {
    OciServeCoursesSection.data => l10n.d(
      'Bekijk welke gegevens eLearning voor u heeft geregistreerd.',
    ),
    OciServeCoursesSection.evidence => l10n.d(
      'Bekijk welke bewijsstukken u heeft ingediend.',
    ),
    OciServeCoursesSection.progress => l10n.d(
      'Bekijk uw resultaten, activiteit en voortgang per cursus.',
    ),
    OciServeCoursesSection.bookings => l10n.d(
      'Uw klassikale bijeenkomsten: binnenkort en geweest.',
    ),
    OciServeCoursesSection.offerings => l10n.d(
      'Schrijf u zelf in voor een uitvoering van deze organisatie.',
    ),
    OciServeCoursesSection.courses => l10n.d(
      'Ga verder waar u gebleven was, of kies een andere cursus die voor u klaarstaat.',
    ),
  };
}

class OciServeCoursesSidebar extends StatelessWidget {
  const OciServeCoursesSidebar({
    super.key,
    required this.account,
    required this.section,
    required this.onSelect,
  });

  final OciServeAccount account;
  final OciServeCoursesSection section;
  final ValueChanged<OciServeCoursesSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final l10n = context.l10n;
    final name = account.displayName.trim().isEmpty
        ? l10n.d('Cursist')
        : account.displayName;
    return SizedBox(
      width: 210,
      child: ColoredBox(
        color: palette.panel,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondary,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.school_outlined,
                      color: AppTheme.labelOn(theme.colorScheme.secondary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.d('eLearning'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: palette.panelText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              // De bestemmingen scrollen als het venster lager is dan de lijst;
              // de accountkaart blijft onderaan verankerd.
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _destination(
                        context,
                        icon: Icons.school_outlined,
                        label: l10n.d('Mijn cursussen'),
                        selected: section == OciServeCoursesSection.courses,
                        onTap: () => onSelect(OciServeCoursesSection.courses),
                      ),
                      const SizedBox(height: 8),
                      _destination(
                        context,
                        icon: Icons.event_available_outlined,
                        label: l10n.d('Mijn inschrijvingen'),
                        selected: section == OciServeCoursesSection.bookings,
                        onTap: () => onSelect(OciServeCoursesSection.bookings),
                      ),
                      const SizedBox(height: 8),
                      _destination(
                        context,
                        icon: Icons.app_registration_outlined,
                        label: l10n.d('Aanbod'),
                        selected: section == OciServeCoursesSection.offerings,
                        onTap: () => onSelect(OciServeCoursesSection.offerings),
                      ),
                      const SizedBox(height: 8),
                      _destination(
                        context,
                        icon: Icons.insights_outlined,
                        label: l10n.d('Mijn voortgang'),
                        selected: section == OciServeCoursesSection.progress,
                        onTap: () => onSelect(OciServeCoursesSection.progress),
                      ),
                      const SizedBox(height: 8),
                      _destination(
                        context,
                        icon: Icons.manage_search_outlined,
                        label: l10n.d('Mijn gegevens'),
                        selected: section == OciServeCoursesSection.data,
                        onTap: () => onSelect(OciServeCoursesSection.data),
                      ),
                      const SizedBox(height: 8),
                      _destination(
                        context,
                        icon: Icons.verified_outlined,
                        label: l10n.d('Mijn bewijs'),
                        selected: section == OciServeCoursesSection.evidence,
                        onTap: () => onSelect(OciServeCoursesSection.evidence),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(color: palette.panelText.withValues(alpha: 0.18)),
              const SizedBox(height: 8),
              _profileCard(context, palette, name),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileCard(BuildContext context, AppPalette palette, String name) {
    final l10n = context.l10n;
    return Semantics(
      button: true,
      label: l10n.d('Bekijk mijn voortgang'),
      child: InkWell(
        key: const Key('ociserve-learning-profile-button'),
        onTap: () => onSelect(OciServeCoursesSection.progress),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              OciServeAccountAvatar(account: account, name: name),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.panelText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      l10n.d('Bekijk uw resultaten'),
                      style: TextStyle(
                        color: palette.panelText.withValues(alpha: 0.72),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: palette.panelText.withValues(alpha: 0.72),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _destination(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final palette = AppPalette.of(Theme.of(context));
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? palette.panelText.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Icon(icon, size: 19, color: palette.panelText),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: palette.panelText,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
