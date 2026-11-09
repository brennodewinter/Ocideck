part of '../app_shell.dart';

/// Het kopje boven de naam van het opgeleverde pakket. Op web is dat geen
/// bestand op een pad maar een aangeboden download — zie [exportDeliveryLabel].
String _packageDeliveredLabel(AppLocalizations l10n) => deliversByDownload
    ? exportDeliveryLabel(l10n)
    : l10n.d('Pakket geëxporteerd naar:');

/// Wat er staat als de browser de download niet aannam.
String _downloadRefusedMessage(AppLocalizations l10n) => l10n.d(
  'De browser heeft de download niet aangenomen. Sta downloads voor deze site toe en probeer het opnieuw.',
);

ExportDecision _fullTransferExportDecision(Deck deck, AppSettings settings) {
  final policy = ClassificationEnforcementPolicy.fromAppSettings(settings);
  // Het deck zelf moet aan de verplichte classificatie en ondergrens voldoen;
  // voor het vrijgaveplafond telt ook de strengste dia mee.
  final deckDecision = policy.evaluate(deck.tlp);
  return deckDecision.allowed
      ? policy.evaluate(deckReleaseTlp(deck))
      : deckDecision;
}

/// Exporteer het huidige deck als zelfstandig `.ocideck`-pakket. Toont eerst de
/// [PackageEncryptDialog] zodat de gebruiker het pakket optioneel met een
/// wachtwoord (AES-256) kan beschermen; annuleren daar breekt de export af. Op
/// web wordt het pakket in het geheugen gebouwd en als download aangeboden.
Future<void> _exportPackage(BuildContext context, WidgetRef ref) async {
  final deck = ref.read(deckProvider).deck!;
  // De classificatiepoort, ook hier. Dit pad ging er volledig omheen terwijl
  // ARCHITECTURE.md het pakket bij name noemt: "no format (PDF/PPTX/HTML/package)
  // can bypass the gate". Een pakket is bovendien de meest complete uitvoer die
  // de app kent — de volledige markdown plus élke asset — dus juist hier telt
  // het plafond.
  //
  final decision = _fullTransferExportDecision(
    deck,
    ref.read(settingsProvider),
  );
  if (!decision.allowed) {
    showErrorSnackBar(
      ScaffoldMessenger.of(context),
      context.l10n,
      exportBlockMessage(context.l10n, decision) ?? '',
    );
    return;
  }
  final privacyDecision = PrivacyExportPolicy(
    gate: ref.read(settingsProvider).privacyExportGate,
  ).evaluate(ref.read(privacyExportSummaryProvider));
  if (!context.mounted ||
      !await confirmDocumentPrivacyExport(context, privacyDecision)) {
    return;
  }
  if (!context.mounted) return;
  final choice = await PackageEncryptDialog.show(context);
  if (choice == null || !context.mounted) return;
  final password = choice.encrypt ? choice.password : null;
  final l10n = context.l10n;
  final fileService = ref.read(fileServiceProvider);
  try {
    final String? dest;
    if (deliversByDownload) {
      dest = await fileService.downloadPackage(deck, password: password);
    } else {
      final picked = await fileService.pickPackageDestination(deck);
      if (picked == null) return;
      await fileService.exportPackage(deck, picked, password: password);
      dest = picked;
    }
    if (!context.mounted) return;
    // `null` komt alleen van de webtak: de browser nam de download niet aan.
    // Een naam melden die nergens staat is erger dan de fout melden (#1902).
    if (dest == null) {
      showErrorSnackBar(
        ScaffoldMessenger.of(context),
        l10n,
        _downloadRefusedMessage(l10n),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_packageDeliveredLabel(l10n)}\n$dest')),
    );
  } catch (e) {
    logError('AppShell: pakketexport mislukt', e);
    if (!context.mounted) return;
    showErrorSnackBar(
      ScaffoldMessenger.of(context),
      l10n,
      '${l10n.d('Export mislukt:')} ${userFacingError(l10n, e)}',
    );
  }
}

/// Open the search-based presentation picker and load the chosen file
/// (optionally jumping to a matched slide). Scans every configured library.
