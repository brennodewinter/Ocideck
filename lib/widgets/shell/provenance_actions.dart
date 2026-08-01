// Part of the app_shell library — see app_shell.dart.
// De herkomstbewijs-acties (Blok C): het ondertekenen aansturen en het
// commandopalet-commando eromheen. Apart bestand zodat de zware logica niet in
// app_shell_main_layout.dart of het commandopalet meetelt voor hun grootte-ratchets.
part of '../app_shell.dart';

/// De "Herkomst ondertekenen"-actie (Blok C): alleen op een afgerond deck met een
/// Matrix-identiteit om mee te tekenen. Top-level (niet op _MainLayoutState) om de
/// klasseomvang onder de ratchet te houden.
List<PaletteCommand> provenanceSignCommands(
  WidgetRef ref,
  AppLocalizations l10n,
  Deck deck,
  VoidCallback onSign,
) {
  if (!(deck.finalized &&
      (ref.read(matrixAccountProvider)?.isConfigured ?? false))) {
    return const [];
  }
  return [
    PaletteCommand(
      label: l10n.d('Herkomst ondertekenen'),
      icon: Icons.workspace_premium_outlined,
      keywords: const [
        'provenance',
        'herkomst',
        'ondertekenen',
        'sign',
        'handtekening',
      ],
      onInvoke: onSign,
    ),
  ];
}

/// Sign the finalised, saved deck's provenance with the collaboration identity
/// (COLLABORATION Phase 2 "Blok C"): a recipient who verified this identity's
/// fingerprint can confirm the deck came from its owner. The signature is over
/// the saved seal hash, so the deck must be finalised and saved with no pending
/// edits; [save] then writes it into `<name>.seal.json`. Top-level to keep
/// `_MainLayoutState` under the class-size ratchet; async gaps are guarded on
/// `context.mounted`.
Future<void> runProvenanceSigning(
  BuildContext context,
  WidgetRef ref, {
  required Future<void> Function() save,
}) async {
  final l10n = context.l10n;
  final deckState = ref.read(deckProvider);
  final deck = deckState.deck;
  final account = ref.read(matrixAccountProvider);
  if (deck == null || account == null) return;
  if (!deck.finalized || deck.sealHash.isEmpty || deckState.isDirty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.d(
            'Rond de presentatie eerst af en sla haar op; daarna kun je de herkomst ondertekenen.',
          ),
        ),
      ),
    );
    return;
  }
  try {
    final keys = await loadOrCreateDeviceKeys(
      secretStore: ref.read(secretStoreProvider),
      homeserver: account.homeserverUrl,
      userId: account.userId,
      deviceId: account.deviceId,
    );
    final signed = await signDeckProvenance(deck, keys);
    if (!context.mounted) return;
    ref.read(deckProvider.notifier).applyProvenance(signed.provenance);
    await save();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.d('Herkomst ondertekend.'))));
  } catch (e) {
    logError('runProvenanceSigning failed', e);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.d('De herkomst kon niet worden ondertekend.')),
        ),
      );
    }
  }
}
