import 'package:material_ui/material_ui.dart';

import '../resizable_dialog_box.dart';
import 'dialog_shell.dart';

/// Gedeelde presentatie van de Git-, S3- en WebDAV-bladeraars.
///
/// Providers, paden, filters en getypeerde resultaten blijven bewust in de
/// drie domeindialogen. Alleen wat de gebruiker als één familie herkent leeft
/// hier: venster, kop, navigatiestrook, inhoud en voet.
class RemoteBrowserDialogChrome extends StatelessWidget {
  const RemoteBrowserDialogChrome({
    super.key,
    required this.title,
    required this.icon,
    required this.body,
    required this.cancelLabel,
    required this.onCancel,
    this.subtitle,
    this.navigation,
    this.initialWidth = 560,
    this.height = 560,
  });

  final String title;
  final IconData icon;
  final Widget body;
  final String cancelLabel;
  final VoidCallback onCancel;
  final Widget? subtitle;
  final Widget? navigation;
  final double initialWidth;
  final double height;

  @override
  Widget build(BuildContext context) => OciDialogShell(
    maxWidth: 960,
    maxHeight: 760,
    child: ResizableDialogBox(
      initialWidth: initialWidth,
      height: height,
      builder: (context, handle) => OciDialogScaffold(
        title: title,
        leading: Icon(icon),
        subtitle: subtitle,
        bodyPadding: EdgeInsets.zero,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (navigation != null) ...[navigation!, const Divider(height: 1)],
            Expanded(child: body),
          ],
        ),
        footerLeading: handle,
        actions: [TextButton(onPressed: onCancel, child: Text(cancelLabel))],
      ),
    ),
  );
}

class RemoteBrowserMessage extends StatelessWidget {
  const RemoteBrowserMessage({
    super.key,
    required this.text,
    required this.icon,
    this.retryLabel,
    this.onRetry,
  }) : assert((retryLabel == null) == (onRetry == null));

  final String text;
  final IconData icon;
  final String? retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(retryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
