import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../services/webdav_service.dart';
import '../../state/webdav_provider.dart';
import 'remote_browser_dialog_chrome.dart';

/// Wat de browser laat kiezen: een deck om te openen of een afbeelding om in te
/// voegen. Bepaalt welke bestanden klikbaar zijn.
enum WebdavBrowseMode { deck, image }

/// Bladert door de geconfigureerde Nextcloud/WebDAV-map en geeft het gekozen
/// bestand ([WebdavEntry]) terug, of `null` bij annuleren. Het ophalen/openen
/// zelf doet de aanroeper (zodat de security-gate en foutmeldingen daar leven).
class WebdavBrowserDialog extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return RemoteBrowserDialogCore<WebdavEntry>(
      selection: mode == WebdavBrowseMode.image
          ? RemoteBrowserSelection.image
          : RemoteBrowserSelection.deck,
      config: RemoteBrowserConfig<WebdavEntry>(
        title: mode == WebdavBrowseMode.image
            ? l10n.d('Afbeelding kiezen op WebDAV')
            : l10n.d('Openen vanaf WebDAV'),
        icon: Icons.cloud_outlined,
        emptyText: l10n.d('Deze map is leeg'),
        listing: (ref, path) => ref.watch(
          webdavListingProvider((connectionId: connectionId, remotePath: path)),
        ),
        refresh: (ref, path) => ref.invalidate(
          webdavListingProvider((connectionId: connectionId, remotePath: path)),
        ),
        nameOf: (entry) => entry.name,
        pathOf: (entry) => entry.relativePath,
        isCollection: (entry) => entry.isCollection,
        isImage: (entry) => entry.isImage,
        isDeck: (entry) => entry.isOcideck || entry.isMarkdown,
      ),
      onSelected: (entry) => Navigator.pop(context, entry),
    );
  }
}
