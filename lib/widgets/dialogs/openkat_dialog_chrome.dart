import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// Gedeelde titel voor alle OpenKAT-vensters.
///
/// De rapportbouwer, serverkiezer en installatiewizard zijn één gebruikersreis.
/// Door titel, merkbeeld en stapstatus hier te delen voelen die vensters ook als
/// één onderdeel van OciDeck, in plaats van drie los ontworpen hulpmiddelen.
class OpenKatDialogTitle extends StatelessWidget {
  const OpenKatDialogTitle({
    super.key,
    required this.title,
    this.currentStep,
    this.totalSteps,
    this.statusText,
    this.trailing,
  });

  final String title;
  final int? currentStep;
  final int? totalSteps;
  final String? statusText;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = currentStep == null || totalSteps == null
        ? statusText
        : '${context.l10n.d('Stap')} $currentStep ${context.l10n.d('van')} $totalSteps';
    final heading = Row(
      children: [
        Image.asset(
          'assets/images/openkat-logo.png',
          width: 32,
          height: 32,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (status != null) ...[
                const SizedBox(height: 2),
                Text(
                  status,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppPalette.of(theme).accentInk,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    if (trailing == null) return heading;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 680 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.4;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 12), trailing!],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            const SizedBox(width: 18),
            trailing!,
          ],
        );
      },
    );
  }
}

enum OpenKatStatusKind { neutral, success, error }

/// Compact statusvlak dat laad-, succes- en foutmeldingen gelijk weergeeft.
class OpenKatStatusBanner extends StatelessWidget {
  const OpenKatStatusBanner({
    super.key,
    required this.text,
    this.kind = OpenKatStatusKind.neutral,
    this.busy = false,
  });

  final String text;
  final OpenKatStatusKind kind;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground, border, icon) = switch (kind) {
      OpenKatStatusKind.success => (
        AppTheme.successBg,
        AppTheme.successFg,
        AppTheme.successBgSoft,
        Icons.check_circle_outline,
      ),
      OpenKatStatusKind.error => (
        AppTheme.dangerBg,
        AppTheme.dangerFg,
        AppTheme.dangerBgSoft,
        Icons.error_outline,
      ),
      OpenKatStatusKind.neutral => (
        colors.surfaceContainerLow,
        colors.onSurfaceVariant,
        colors.outlineVariant,
        Icons.info_outline,
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (busy)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            else
              Icon(icon, size: 20, color: foreground),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: foreground,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
