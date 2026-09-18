import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/webdav_service.dart';
import '../../state/webdav_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/user_facing_error.dart';
import 'remote_browser_dialog_chrome.dart';

/// Wat de browser laat kiezen: een deck om te openen of een afbeelding om in te
/// voegen. Bepaalt welke bestanden klikbaar zijn.
enum WebdavBrowseMode { deck, image }

/// Bladert door de geconfigureerde Nextcloud/WebDAV-map en geeft het gekozen
/// bestand ([WebdavEntry]) terug, of `null` bij annuleren. Het ophalen/openen
/// zelf doet de aanroeper (zodat de security-gate en foutmeldingen daar leven).
class WebdavBrowserDialog extends ConsumerStatefulWidget {
  final WebdavBrowseMode mode;

  /// Op welke verbinding gebladerd wordt. Meegegeven en niet zelf uit de
  /// instellingen gelezen: de aanroeper heeft de gebruiker al laten kiezen, en
  /// die keuze mag hier niet stilletjes een andere worden.
  final String connectionId;

  const WebdavBrowserDialog({
    super.key,
    required this.mode,
    required this.connectionId,
  });

  static Future<WebdavEntry?> show(
    BuildContext context, {
    required String connectionId,
    WebdavBrowseMode mode = WebdavBrowseMode.deck,
  }) {
    return showDialog<WebdavEntry>(
      context: context,
      builder: (_) =>
          WebdavBrowserDialog(mode: mode, connectionId: connectionId),
    );
  }

  @override
  ConsumerState<WebdavBrowserDialog> createState() =>
      _WebdavBrowserDialogState();
}

class _WebdavBrowserDialogState extends ConsumerState<WebdavBrowserDialog> {
  /// Pad relatief aan de wortelmap; leeg = wortel.
  String _path = '';

  /// De cachesleutel voor een pad op déze verbinding.
  WebdavListingKey _key(String remotePath) =>
      (connectionId: widget.connectionId, remotePath: remotePath);

  void _navigateTo(String relativePath) {
    setState(() => _path = relativePath);
  }

  void _goUp() {
    final i = _path.lastIndexOf('/');
    setState(() => _path = i < 0 ? '' : _path.substring(0, i));
  }

  bool _isSelectable(WebdavEntry entry) {
    if (entry.isCollection) return false;
    return widget.mode == WebdavBrowseMode.image
        ? entry.isImage
        : (entry.isOcideck || entry.isMarkdown);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final listing = ref.watch(webdavListingProvider(_key(_path)));
    final title = widget.mode == WebdavBrowseMode.image
        ? l10n.d('Afbeelding kiezen op WebDAV')
        : l10n.d('Openen vanaf WebDAV');

    return RemoteBrowserDialogChrome(
      title: title,
      icon: Icons.cloud_outlined,
      navigation: _breadcrumb(l10n),
      body: listing.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _error(l10n, error),
        data: (entries) => _list(l10n, entries),
      ),
      cancelLabel: l10n.t('cancel'),
      onCancel: () => Navigator.pop(context),
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
            onPressed: () => ref.invalidate(webdavListingProvider(_key(_path))),
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

  Widget _list(AppLocalizations l10n, List<WebdavEntry> entries) {
    final visible = widget.mode == WebdavBrowseMode.image
        ? entries.where((e) => e.isCollection || e.isImage).toList()
        : entries
              .where((e) => e.isCollection || e.isOcideck || e.isMarkdown)
              .toList();
    if (visible.isEmpty) {
      return RemoteBrowserMessage(
        text: l10n.d('Deze map is leeg'),
        icon: Icons.folder_off_outlined,
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
    return RemoteBrowserMessage(
      // Was: alleen "niet ingesteld" apart, al het andere platgeslagen tot één
      // algemene fout, terwijl de tabel hier de echte oorzaak kan noemen.
      text: userFacingError(l10n, error),
      icon: Icons.cloud_off,
      retryLabel: l10n.d('Opnieuw proberen'),
      onRetry: () => ref.invalidate(webdavListingProvider(_key(_path))),
    );
  }
}
