import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ociserve_file_contract/ociserve_file_contract.dart';
import '../../l10n/app_localizations.dart';
import '../../services/ociserve/ociserve_gateway.dart';
import '../../state/ociserve_provider.dart';
import '../../state/tabs_provider.dart';
import '../../utils/error_snackbar.dart';
import '../dialogs/ociserve_file_browser.dart';
import '../dialogs/ociserve_file_shares.dart';
import 'open_failure_message.dart';

bool isOciServeShareUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  return uri != null && FileShareLink.resembles(uri);
}

Future<void> openOciServeFiles(BuildContext context, WidgetRef ref) async {
  final selection = await OciServeFileBrowser.show(context);
  if (selection != null && context.mounted) {
    await _openOciServeSelection(context, ref, selection);
  }
}

Future<void> _openOciServeSelection(
  BuildContext context,
  WidgetRef ref,
  OciServeFileSelection selection,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final result = await ref
      .read(tabsProvider.notifier)
      .openDeckFromBytes(selection.bytes, selection.entry.name);
  if (!context.mounted) return;
  if (result == OpenResult.opened) {
    ref.read(tabsProvider).current?.ociServeOrigin = selection.origin;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          l10n.d(
            'Lokale kopie geopend. Opslaan wijzigt het OciServe-bestand niet.',
          ),
        ),
      ),
    );
  } else {
    if (result == OpenResult.unreadable ||
        result == OpenResult.notAPresentation) {
      showErrorSnackBar(
        messenger,
        l10n,
        openFailureMessage(l10n, ref.read(openFailureProvider)),
      );
    }
  }
}

/// Resolved before media probes, proxy fallback, URL persistence or generic
/// error logging. A malformed capability link must never reach those paths.
Future<bool> tryOpenOciServeShare(
  BuildContext context,
  WidgetRef ref,
  String raw,
) async {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !FileShareLink.resembles(uri)) return false;
  try {
    final link = FileShareLink.parse(raw);
    // Only a previously and explicitly trusted server can opt into private
    // DNS. Trust never follows the signed-in account to an unrelated origin.
    final settings = ref.read(ociServeProvider).settings;
    final trusted =
        settings.trustedInternal &&
        settings.isConfigured &&
        Uri.parse(settings.normalizedBaseUrl).origin == link.origin.origin;
    final client = OciServePublicFiles(link, trustedInternal: trusted);
    final selection = await OciServeFileBrowser.show(
      context,
      publicFiles: client,
    );
    if (selection != null && context.mounted) {
      await _openOciServeSelection(context, ref, selection);
    }
  } catch (e) {
    if (context.mounted) {
      showErrorSnackBar(
        ScaffoldMessenger.of(context),
        context.l10n,
        ociServeFileError(context, e),
      );
    }
  }
  return true;
}

Future<void> shareOciServeCurrent(BuildContext context, WidgetRef ref) async {
  final origin = ref.read(tabsProvider).current?.ociServeOrigin;
  if (origin == null || origin.publicShare || origin.organizationId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.d(
            'Delen vereist een gepubliceerd OciServe-bestand. Sla een lokaal bestand eerst bewust op bij de organisatie en open het via OciServe.',
          ),
        ),
      ),
    );
    return;
  }
  final settings = ref.read(ociServeProvider).settings;
  if (!settings.isConfigured ||
      Uri.parse(settings.normalizedBaseUrl).origin !=
          Uri.parse(origin.server).origin) {
    showErrorSnackBar(
      ScaffoldMessenger.of(context),
      context.l10n,
      context.l10n.d('Meld u aan bij de oorspronkelijke OciServe-server.'),
    );
    return;
  }
  // The server pins the published version at create time. The dialog
  // explicitly distinguishes that snapshot from unpublished local edits.
  await OciServeFileShares.show(
    context,
    organizationId: origin.organizationId!,
    target: CatalogEntry(
      id: origin.fileId,
      name: origin.name,
      directory: false,
      etag: origin.etag,
    ),
  );
}
