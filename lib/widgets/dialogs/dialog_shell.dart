import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../theme/app_theme.dart';

/// De gedeelde buitenvorm voor taakvensters van OciDeck.
///
/// Deze widget bezit alleen geometrie en uiterlijk. Sluitgedrag, navigatie,
/// laden en domeinbesluiten blijven bij de aanroeper, omdat een bestandsbrowser
/// een ander contract heeft dan bijvoorbeeld een export.
class OciDialogShell extends StatelessWidget {
  const OciDialogShell({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.maxWidth = 1040,
    this.maxHeight = 860,
    this.alignment = Alignment.center,
  });

  static const double radius = 18;

  final Widget child;
  final double? width;
  final double? height;
  final double maxWidth;
  final double maxHeight;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final compact = viewport.width < 720 || viewport.height < 620;
    final inset = compact
        ? const EdgeInsets.all(12)
        : const EdgeInsets.symmetric(horizontal: 40, vertical: 28);
    final availableWidth = math.max(0.0, viewport.width - inset.horizontal);
    final availableHeight = math.max(0.0, viewport.height - inset.vertical);
    final boundedWidth = math.min(maxWidth, availableWidth);
    final boundedHeight = math.min(maxHeight, availableHeight);

    Widget content = ConstrainedBox(
      key: width == null && height == null
          ? const Key('oci-dialog-surface')
          : null,
      constraints: BoxConstraints(
        maxWidth: boundedWidth,
        maxHeight: boundedHeight,
      ),
      child: child,
    );
    if (width != null || height != null) {
      content = SizedBox(
        key: const Key('oci-dialog-surface'),
        width: width == null ? null : math.min(width!, boundedWidth),
        height: height == null ? null : math.min(height!, boundedHeight),
        child: content,
      );
    }

    final theme = Theme.of(context);
    return Dialog(
      alignment: alignment,
      insetPadding: inset,
      clipBehavior: Clip.antiAlias,
      backgroundColor:
          theme.dialogTheme.backgroundColor ?? theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(radius)),
      ),
      child: content,
    );
  }
}

/// Vaste kop, inhoud en voet binnen een [OciDialogShell].
class OciDialogScaffold extends StatelessWidget {
  const OciDialogScaffold({
    super.key,
    required this.title,
    required this.body,
    required this.actions,
    this.leading,
    this.subtitle,
    this.headerTrailing,
    this.footerLeading,
    this.bodyPadding = const EdgeInsets.all(20),
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final Widget? leading;
  final Widget? subtitle;
  final Widget? headerTrailing;
  final Widget? footerLeading;
  final EdgeInsetsGeometry bodyPadding;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OciDialogHeader(
        title: title,
        leading: leading,
        subtitle: subtitle,
        trailing: headerTrailing,
      ),
      const Divider(height: 1),
      Expanded(
        child: Padding(padding: bodyPadding, child: body),
      ),
      const Divider(height: 1),
      OciDialogFooter(leading: footerLeading, actions: actions),
    ],
  );
}

class OciDialogHeader extends StatelessWidget {
  const OciDialogHeader({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final Widget? leading;
  final Widget? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleBlock = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leading != null) ...[
          IconTheme(
            data: IconThemeData(
              color: AppPalette.of(theme).accentInk,
              size: 22,
            ),
            child: leading!,
          ),
          const SizedBox(width: 12),
        ],
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
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                DefaultTextStyle(
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  child: subtitle!,
                ),
              ],
            ],
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 520 ||
              MediaQuery.textScalerOf(context).scale(1) >= 1.5;
          if (trailing == null) return titleBlock;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleBlock,
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: trailing,
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: titleBlock),
              const SizedBox(width: 18),
              trailing!,
            ],
          );
        },
      ),
    );
  }
}

class OciDialogFooter extends StatelessWidget {
  const OciDialogFooter({super.key, required this.actions, this.leading});

  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final actionWrap = Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: actions,
        );
        final stacked =
            constraints.maxWidth < 460 ||
            MediaQuery.textScalerOf(context).scale(1) >= 1.5;
        if (leading == null)
          return Align(
            alignment: AlignmentDirectional.centerEnd,
            child: actionWrap,
          );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: leading,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: actionWrap,
              ),
            ],
          );
        }
        return Row(
          children: [
            leading!,
            const Spacer(),
            Flexible(child: actionWrap),
          ],
        );
      },
    ),
  );
}
