import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../services/s3/s3_service.dart';
import '../../state/s3_provider.dart';
import 'remote_browser_dialog_chrome.dart';

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
class S3BrowserDialog extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return RemoteBrowserDialogCore<S3Entry>(
      selection: mode == S3BrowseMode.image
          ? RemoteBrowserSelection.image
          : RemoteBrowserSelection.deck,
      config: RemoteBrowserConfig<S3Entry>(
        title: mode == S3BrowseMode.image
            ? l10n.d('Afbeelding kiezen in S3')
            : l10n.d('Openen vanuit S3'),
        icon: Icons.inventory_2_outlined,
        emptyText: l10n.d('Hier staat niets'),
        listing: (ref, path) => ref.watch(
          s3ListingProvider((connectionId: connectionId, remotePath: path)),
        ),
        refresh: (ref, path) => ref.invalidate(
          s3ListingProvider((connectionId: connectionId, remotePath: path)),
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
