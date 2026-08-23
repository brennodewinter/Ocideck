import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../services/scope_coverage.dart';
import '../../theme/app_theme.dart';

/// Shows the scope-coverage gaps (PENTEST_MIAUW §10.4) — scope objects that are
/// in scope but neither tested nor referenced by a finding. The [gaps] are
/// computed at the (tab-scoped) call site and passed in, so this dialog stays a
/// plain, scope-independent [StatelessWidget].
class ScopeCoverageDialog extends StatelessWidget {
  const ScopeCoverageDialog({super.key, required this.gaps});

  final List<ScopeGap> gaps;

  static Future<void> show(BuildContext context, List<ScopeGap> gaps) =>
      showDialog<void>(
        context: context,
        builder: (_) => ScopeCoverageDialog(gaps: gaps),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Scope-dekking')),
      content: SizedBox(
        width: 460,
        child: gaps.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: AppTheme.successFg,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(l10n.d('Geen dekkingsgaten'))),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.d('In scope, maar niet getest en geen bevinding:'),
                    style: TextStyle(fontSize: 12, color: AppTheme.slate500),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final gap in gaps)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.warning_amber_outlined,
                              size: 18,
                              color: AppTheme.amber700,
                            ),
                            title: Text(gap.object),
                            subtitle: Text(gap.type.dutchLabel),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Sluiten')),
        ),
      ],
    );
  }
}
