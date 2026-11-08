import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../services/browser_deck_store.dart';
import '../../services/file_service.dart';
import '../../state/deck_provider.dart';
import '../../utils/log.dart';
import 'settings/extension_consent.dart';

const browserStorageWarning =
    'Browseropslag is onversleuteld en toegankelijk voor andere gebruikers van dit profiel en scripts op deze website. Wissen van websitegegevens, privémodus of ruimtegebrek kan uw werk verwijderen. Bewaren op de lokale schijf is veiliger: u beheert zelf toegang en reservekopieën.';

/// null = geannuleerd; false = download; true = in browser bewaard.
Future<bool?> chooseBrowserSave(
  BuildContext context,
  DeckNotifier notifier,
  FileService files,
) async {
  final l10n = context.l10n;
  final choice = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.d('Presentatie opslaan')),
      content: Text(l10n.d('Waar wilt u de presentatie bewaren?')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.t('cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.d('In browser bewaren')),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.d('Als bestand downloaden')),
        ),
      ],
    ),
  );
  if (choice != true || !context.mounted) return choice;
  if (!await confirmDataImpact(
        context,
        id: 'browser-storage',
        title: l10n.d('In browser bewaren'),
        warning: l10n.d(browserStorageWarning),
      ) ||
      !context.mounted) {
    return null;
  }
  final snapshot = notifier.currentState;
  final deck = snapshot.deck;
  if (deck == null) return null;
  try {
    final bytes = await files.buildPackageBytes(
      deck,
      budgetBytes: BrowserDeckStore.maxEncodedLength,
    );
    final id = await BrowserDeckStore().save(
      deck.title,
      bytes,
      id: notifier.browserStorageId,
    );
    notifier.browserStorageId = id;
    final currentSaved = notifier.markBrowserSaved(deck, snapshot.revision);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.d('Bewaard in browser. Heropenen via Instellingen → Opslag.'),
          ),
        ),
      );
    }
    return currentSaved ? true : null;
  } catch (e, s) {
    logError('browser-storage: save failed', e, s);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.d(
              'Browseropslag mislukt. Download uw presentatie als bestand.',
            ),
          ),
        ),
      );
    }
    return null;
  }
}
