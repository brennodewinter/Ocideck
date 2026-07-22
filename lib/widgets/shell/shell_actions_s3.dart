// Part of the app_shell library — see ../app_shell.dart.
//
// Openen vanuit en opslaan naar een S3-bucket. Apart bestand omdat
// `shell_actions` tegen de regelratchet aan zit; het opslaan- en
// conflictdialoog worden gedeeld met het WebDAV-pad, want het is voor de
// gebruiker dezelfde vraag.
part of '../app_shell.dart';

/// Laat de gebruiker een S3-verbinding kiezen. Bij één verbinding gebeurt dat
/// zonder dialoog; bij geen enkele volgt de melding dat er niets staat
/// ingesteld.
Future<S3Connection?> _pickS3Connection(
  BuildContext context,
  WidgetRef ref,
) async {
  final connections = ref.read(s3ConnectionsProvider);
  if (connections.isEmpty) {
    _s3NotConfigured(context);
    return null;
  }
  return StorageConnectionPicker.show(context, connections);
}

void _s3NotConfigured(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        context.l10n.d(
          'Stel eerst een S3-bucket in bij Instellingen → Opslag.',
        ),
      ),
    ),
  );
}

/// Blader door de S3-bucket, download het gekozen deck, haal het door de
/// security-gate en open het in een tab.
Future<void> _openFromS3(
  BuildContext context,
  WidgetRef ref, {
  S3Connection? connection,
}) async {
  final chosen = connection ?? await _pickS3Connection(context, ref);
  if (chosen == null || !context.mounted) return;
  final service = await ref.read(s3ServiceProvider(chosen.id).future);
  if (!context.mounted) return;
  if (service == null) {
    _s3NotConfigured(context);
    return;
  }
  final entry = await S3BrowserDialog.show(context, connectionId: chosen.id);
  if (entry == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    final result = await ref
        .read(tabsProvider.notifier)
        .openFromS3(
          service,
          entry,
          connectionId: chosen.id,
          homeDir: ref.read(settingsProvider).homeDirectory,
        );
    _reportOpenFailure(messenger, l10n, result);
    // OpenResult.blocked toont al het veiligheidsalarm via de shell.
  } on S3Exception catch (e) {
    logWarning('shell: S3-download mislukt', e);
    showErrorSnackBar(
      messenger,
      l10n,
      '${l10n.d('Downloaden mislukt:')} ${s3ErrorMessage(l10n, e)}',
    );
  }
}

/// Schrijf het deck van het huidige tabblad terug naar S3. Vraagt het formaat
/// (pakket of platte bestanden) en het doelpad, en uploadt dan.
/// Slaat het actieve deck op naar S3. Geeft terug of er daadwerkelijk is
/// opgeslagen. Zie [_saveToNextcloud] voor wat [silent] betekent; dit pad
/// spiegelt dat.
Future<bool> _saveToS3(
  BuildContext context,
  WidgetRef ref, {
  bool silent = false,
  S3Connection? connectionOverride,
}) async {
  final tab = ref.read(tabsProvider).current;
  final deck = tab?.deckNotifier.currentState.deck;
  if (tab == null || deck == null) return false;
  // Kwam dit deck van een S3-verbinding die nog bestaat, dan gaat het
  // daarnaartoe terug zonder te vragen. Opnieuw laten kiezen zou de gebruiker
  // elke keer de kans geven het bij de verkeerde klant te laten belanden.
  final origin = tab.s3Origin;
  final settings = ref.read(settingsProvider);
  final known = settings.connectionById(origin?.connectionId);
  // Een expliciet gekozen doel wint van de herkomst: dat is precies wat
  // "Opslaan naar…" betekent.
  final connection =
      connectionOverride ??
      (known is S3Connection && known.isConfigured
          ? known
          : await _pickS3Connection(context, ref));
  if (connection == null || !context.mounted) return false;

  final service = await ref.read(s3ServiceProvider(connection.id).future);
  if (!context.mounted) return false;
  if (service == null) {
    _s3NotConfigured(context);
    return false;
  }
  // Standaardpad: hergebruik de herkomst als die uit dezelfde bucket komt,
  // anders een nette bestandsnaam uit de deck-titel in de wortelprefix.
  final reuse = origin != null && origin.matchesBucket(service.bucket);
  final defaultBase = reuse
      ? origin.remotePath.replaceAll(RegExp(r'\.(ocideck|zip|md)$'), '')
      : _safeRemoteName(deck.title);
  var choice = silent && reuse
      ? (format: _formatOfRemotePath(origin.remotePath), base: defaultBase)
      : await _showRemoteSaveDialog(
          context,
          defaultBase: defaultBase,
          title: context.l10n.d('Opslaan naar S3'),
        );
  if (choice == null || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  // Blijft doorlopen zolang de gebruiker na een botsing een andere weg kiest:
  // onder een nieuwe naam opslaan, of alsnog overschrijven.
  var overwrite = false;
  while (true) {
    final ext = choice!.format == DeckSaveFormat.ocideck ? '.ocideck' : '.md';
    final targetPath = '${choice.base}$ext';
    try {
      await withSaveProgress(
        ref,
        SaveTarget.s3,
        () => ref
            .read(tabsProvider.notifier)
            .saveToS3(
              tab,
              service,
              connectionId: connection.id,
              format: choice!.format,
              targetPath: targetPath,
              overwrite: overwrite,
            ),
      );
      // Het opslaan is geslaagd; alleen de melding kan niet meer getoond worden.
      if (!context.mounted) return true;
      messenger.showSnackBar(
        SnackBar(content: Text('${l10n.d('Opgeslagen in S3:')} /$targetPath')),
      );
      return true;
    } on S3ConflictException catch (e) {
      logWarning('shell: S3-opslaan botste met een nieuwere versie', e);
      if (!context.mounted) return false;
      final resolution = await _showRemoteConflictDialog(context);
      if (resolution == null || !context.mounted) return false;
      switch (resolution) {
        case _RemoteConflict.overwrite:
          overwrite = true;
        case _RemoteConflict.saveAs:
          final next = await _showRemoteSaveDialog(
            context,
            defaultBase: choice.base,
            title: l10n.d('Opslaan naar S3'),
          );
          if (next == null || !context.mounted) return false;
          choice = next;
          // Een ander doelpad wordt niet bewaakt (we haalden het nooit op),
          // maar een ongewijzigd pad moet de guard hóuden.
          overwrite = false;
      }
    } on S3Exception catch (e) {
      logWarning('shell: S3-opslaan mislukt', e);
      showErrorSnackBar(
        messenger,
        l10n,
        '${l10n.d('Opslaan mislukt:')} ${s3ErrorMessage(l10n, e)}',
      );
      return false;
    }
  }
}
