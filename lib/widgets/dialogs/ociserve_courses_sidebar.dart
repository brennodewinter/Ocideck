import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_models.dart';
import '../../theme/app_theme.dart';
import 'ociserve_account_avatar.dart';

class OciServeCoursesSidebar extends StatelessWidget {
  const OciServeCoursesSidebar({
    super.key,
    required this.account,
    required this.showProgress,
    required this.showData,
    required this.onCourses,
    required this.onProgress,
    required this.onData,
  });

  final OciServeAccount account;
  final bool showProgress;
  final bool showData;
  final VoidCallback onCourses;
  final VoidCallback onProgress;
  final VoidCallback onData;

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
              _destination(
                context,
                icon: Icons.school_outlined,
                label: l10n.d('Mijn cursussen'),
                selected: !showProgress && !showData,
                onTap: onCourses,
              ),
              const SizedBox(height: 8),
              _destination(
                context,
                icon: Icons.insights_outlined,
                label: l10n.d('Mijn voortgang'),
                selected: showProgress,
                onTap: onProgress,
              ),
              const SizedBox(height: 8),
              _destination(
                context,
                icon: Icons.manage_search_outlined,
                label: l10n.d('Mijn gegevens'),
                selected: showData,
                onTap: onData,
              ),
              const Spacer(),
              Divider(color: palette.panelText.withValues(alpha: 0.18)),
              const SizedBox(height: 8),
              Semantics(
                button: true,
                label: l10n.d('Bekijk mijn voortgang'),
                child: InkWell(
                  key: const Key('ociserve-learning-profile-button'),
                  onTap: onProgress,
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
                                  color: palette.panelText.withValues(
                                    alpha: 0.72,
                                  ),
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
