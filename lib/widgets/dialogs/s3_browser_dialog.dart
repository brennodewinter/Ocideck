import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/s3/s3_service.dart';
import '../../state/s3_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/user_facing_error.dart';
import '../resizable_dialog_box.dart';

/// Wat de bladeraar laat kiezen: een deck om te openen of een afbeelding om in
/// te voegen. Bepaalt welke objecten klikbaar zijn.
enum S3BrowseMode { deck, image }

/// Bladert door een S3-bucket en geeft het gekozen object ([S3Entry]) terug, of
/// `null` bij annuleren. Het ophalen/openen zelf doet de aanroeper (zodat de
/// security-gate en de foutmeldingen daar leven).
///
/// S3 kent geen mappen; de prefixen die de listing teruggeeft gedragen zich als
/// mappen en komen hier als [S3Entry.isCollection] binnen, zodat dit scherm
/// niets van prefixen hoeft te weten.
class S3BrowserDialog extends ConsumerStatefulWidget {
  final S3BrowseMode mode;

  /// Op welke verbinding gebladerd wordt. Meegegeven en niet zelf uit de
  /// instellingen gelezen: de aanroeper heeft de gebruiker al laten kiezen, en
  /// die keuze mag hier niet stilletjes een andere worden.
  final String connectionId;

  const S3BrowserDialog({
    super.key,
    required this.mode,
    required this.connectionId,
  });

  static Future<S3Entry?> show(
    BuildContext context, {
    required String connectionId,
    S3BrowseMode mode = S3BrowseMode.deck,
  }) {
    return showDialog<S3Entry>(
      context: context,
      builder: (_) => S3BrowserDialog(mode: mode, connectionId: connectionId),
    );
  }

  @override
  ConsumerState<S3BrowserDialog> createState() => _S3BrowserDialogState();
}

class _S3BrowserDialogState extends ConsumerState<S3BrowserDialog> {
  /// Pad relatief aan de wortelprefix; leeg = de wortel.
  String _path = '';

  S3ListingKey _key(String remotePath) =>
      (connectionId: widget.connectionId, remotePath: remotePath);

  void _navigateTo(String relativePath) {
    setState(() => _path = relativePath);
  }

  void _goUp() {
    final i = _path.lastIndexOf('/');
    setState(() => _path = i < 0 ? '' : _path.substring(0, i));
  }

  bool _isSelectable(S3Entry entry) {
    if (entry.isCollection) return false;
    return widget.mode == S3BrowseMode.image
        ? entry.isImage
        : (entry.isOcideck || entry.isMarkdown);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final listing = ref.watch(s3ListingProvider(_key(_path)));
    final title = widget.mode == S3BrowseMode.image
        ? l10n.d('Afbeelding kiezen in S3')
        : l10n.d('Openen vanuit S3');

    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ResizableDialogBox(
        initialWidth: 560,
        height: 560,
        builder: (context, handle) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(title),
            _breadcrumb(l10n),
            const Divider(height: 1),
            Expanded(
              child: listing.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _error(l10n, error),
                data: (entries) => _list(l10n, entries),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  handle,
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.t('cancel')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(String title) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
      color: AppTheme.navy,
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _breadcrumb(AppLocalizations l10n) {
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
            onPressed: () => ref.invalidate(s3ListingProvider(_key(_path))),
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: l10n.d('Vernieuwen'),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Tooltip(
              message: _path.isEmpty ? '/' : '/$_path',
              waitDuration: const Duration(milliseconds: 400),
              child: Text(
                _path.isEmpty ? '/' : '/$_path',
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

  Widget _list(AppLocalizations l10n, List<S3Entry> entries) {
    final visible = widget.mode == S3BrowseMode.image
        ? entries.where((e) => e.isCollection || e.isImage).toList()
        : entries
              .where((e) => e.isCollection || e.isOcideck || e.isMarkdown)
              .toList();
    if (visible.isEmpty) {
      return Center(
        child: Text(
          l10n.d('Hier staat niets'),
          style: TextStyle(color: AppTheme.slate400),
        ),
      );
    }
    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (_, i) {
        final entry = visible[i];
        final selectable = _isSelectable(entry);
        return ListTile(
          dense: true,
          leading: Icon(
            entry.isCollection
                ? Icons.folder_outlined
                : entry.isImage
                ? Icons.image_outlined
                : Icons.slideshow_outlined,
            color: entry.isCollection ? AppTheme.accentFg : AppTheme.slate600,
            size: 20,
          ),
          title: Text(entry.name, style: const TextStyle(fontSize: 13)),
          trailing: entry.isCollection
              ? const Icon(Icons.chevron_right, size: 18)
              : null,
          enabled: entry.isCollection || selectable,
          onTap: entry.isCollection
              ? () => _navigateTo(entry.relativePath)
              : selectable
              ? () => Navigator.pop(context, entry)
              : null,
        );
      },
    );
  }

  Widget _error(AppLocalizations l10n, Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 40, color: AppTheme.slate400),
            const SizedBox(height: 12),
            Text(
              // Alles behalve "niet ingesteld" werd hier platgeslagen tot één
              // zin, terwijl de tabel het onderscheid al kon maken.
              userFacingError(l10n, error),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.slate500),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => ref.invalidate(s3ListingProvider(_key(_path))),
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(l10n.d('Opnieuw proberen')),
            ),
          ],
        ),
      ),
    );
  }
}
