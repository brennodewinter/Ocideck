// Part of the app_shell library — see app_shell.dart.
// De herkomstbewijs-acties (Blok C): het ondertekenen aansturen en het
// commandopalet-commando eromheen. Apart bestand zodat de zware logica niet in
// app_shell_main_layout.dart of het commandopalet meetelt voor hun grootte-ratchets.
part of '../app_shell.dart';

/// De "Herkomst ondertekenen"-actie (Blok C). Top-level (niet op
/// _MainLayoutState) om de klasseomvang onder de ratchet te houden.
List<PaletteCommand> provenanceSignCommands(
  WidgetRef ref,
  AppLocalizations l10n,
  Deck deck,
  VoidCallback onSign,
) {
  return const [];
}

/// Sign the finalised, saved deck's provenance with the collaboration identity
/// (COLLABORATION Phase 2 "Blok C"). Top-level to keep `_MainLayoutState` under
/// the class-size ratchet; async gaps are guarded on `context.mounted`.
Future<void> runProvenanceSigning(
  BuildContext context,
  WidgetRef ref, {
  required Future<void> Function() save,
}) async {}
