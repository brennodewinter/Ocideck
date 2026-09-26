import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/user_facing_error.dart';
import '../resizable_dialog_box.dart';
import 'dialog_shell.dart';

enum RemoteBrowserSelection { deck, image }

typedef RemoteBrowserListing<Entry> =
    AsyncValue<List<Entry>> Function(WidgetRef ref, String remotePath);
typedef RemoteBrowserRefresh = void Function(WidgetRef ref, String remotePath);

/// De protocolgrens van de gedeelde S3- en WebDAV-bladeraar.
///
/// De opslagdiensten houden hun eigen invoertype en provider. Deze configuratie
/// benoemt alleen de eigenschappen die de identieke browserinteractie nodig
/// heeft, zodat er geen tweede opslagmodel naast de services ontstaat.
class RemoteBrowserConfig<Entry> {
  const RemoteBrowserConfig({
    required this.title,
    required this.icon,
    required this.emptyText,
    required this.listing,
    required this.refresh,
    required this.nameOf,
    required this.pathOf,
    required this.isCollection,
    required this.isImage,
    required this.isDeck,
  });

  final String title;
  final IconData icon;
  final String emptyText;
  final RemoteBrowserListing<Entry> listing;
  final RemoteBrowserRefresh refresh;
  final String Function(Entry entry) nameOf;
  final String Function(Entry entry) pathOf;
  final bool Function(Entry entry) isCollection;
  final bool Function(Entry entry) isImage;
  final bool Function(Entry entry) isDeck;
}

/// Gedeelde browserinteractie voor externe opslag met een mapachtig pad.
class RemoteBrowserDialogCore<Entry> extends ConsumerStatefulWidget {
  const RemoteBrowserDialogCore({
    super.key,
    required this.selection,
    required this.config,
    required this.onSelected,
  });

  final RemoteBrowserSelection selection;
  final RemoteBrowserConfig<Entry> config;
  final ValueChanged<Entry> onSelected;

  @override
  ConsumerState<RemoteBrowserDialogCore<Entry>> createState() =>
      _RemoteBrowserDialogCoreState<Entry>();
}

class _RemoteBrowserDialogCoreState<Entry>
    extends ConsumerState<RemoteBrowserDialogCore<Entry>> {
  String _path = '';

  void _navigateTo(String relativePath) {
    setState(() => _path = relativePath);
  }

  void _goUp() {
    final separator = _path.lastIndexOf('/');
    setState(() => _path = separator < 0 ? '' : _path.substring(0, separator));
  }

  bool _isSelectable(Entry entry) =>
      !widget.config.isCollection(entry) &&
      (widget.selection == RemoteBrowserSelection.image
          ? widget.config.isImage(entry)
          : widget.config.isDeck(entry));

  bool _isVisible(Entry entry) =>
      widget.config.isCollection(entry) || _isSelectable(entry);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final config = widget.config;
    final listing = config.listing(ref, _path);

    return RemoteBrowserDialogChrome(
      title: config.title,
      icon: config.icon,
      navigation: _breadcrumb(l10n),
      body: listing.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => RemoteBrowserMessage(
          text: userFacingError(l10n, error),
          icon: Icons.cloud_off,
          retryLabel: l10n.d('Opnieuw proberen'),
          onRetry: () => config.refresh(ref, _path),
        ),
        data: (entries) => _list(entries),
      ),
      cancelLabel: l10n.t('cancel'),
      onCancel: () => Navigator.pop(context),
    );
  }

  Widget _breadcrumb(AppLocalizations l10n) {
    final pathLabel = _path.isEmpty ? '/' : '/$_path';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: _path.isEmpty ? null : _goUp,
            icon: const Icon(Icons.arrow_upward, size: 18),
            tooltip: l10n.d('Omhoog'),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: () => widget.config.refresh(ref, _path),
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: l10n.d('Vernieuwen'),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Tooltip(
              message: pathLabel,
              waitDuration: const Duration(milliseconds: 400),
              child: Text(
                pathLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.slate600,
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(List<Entry> entries) {
    final visible = entries.where(_isVisible).toList();
    if (visible.isEmpty) {
      return RemoteBrowserMessage(
        text: widget.config.emptyText,
        icon: Icons.folder_off_outlined,
      );
    }
    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (_, index) {
        final entry = visible[index];
        final isCollection = widget.config.isCollection(entry);
        return ListTile(
          dense: true,
          leading: Icon(
            isCollection
                ? Icons.folder_outlined
                : widget.config.isImage(entry)
                ? Icons.image_outlined
                : Icons.slideshow_outlined,
            color: isCollection ? AppTheme.accentFg : AppTheme.slate600,
            size: 20,
          ),
          title: Text(
            widget.config.nameOf(entry),
            style: const TextStyle(fontSize: 13),
          ),
          trailing: isCollection
              ? const Icon(Icons.chevron_right, size: 18)
              : null,
          onTap: isCollection
              ? () => _navigateTo(widget.config.pathOf(entry))
              : () => widget.onSelected(entry),
        );
      },
    );
  }
}

/// Gedeelde presentatie van de Git-, S3- en WebDAV-bladeraars.
///
/// S3 en WebDAV gebruiken hierboven ook dezelfde mapinteractie. Git houdt zijn
/// eigen browserkern, omdat takken en revisies geen mapachtig pad vormen, maar
/// deelt wel dit venster, de kop, inhoud en voet.
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
