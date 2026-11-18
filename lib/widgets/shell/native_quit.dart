part of '../app_shell.dart';

/// Bouwt tijdelijke Flutter-oppervlakken af voordat het native venster sluit.
///
/// Een oorspronkelijke macOS-close vernietigt de renderboom onmiddellijk. Als
/// er dan nog een exportdialoog, tooltipanimatie of scrollpositie aan hangt,
/// krijgen die geen normaal dispose-frame meer en volgen assertions uit de
/// semantics- en tickerlagen. Eerst terug naar de wortelroute en één frame
/// laten landen geeft elk tijdelijk oppervlak zijn gewone afbouwpad.
@visibleForTesting
Future<void> settleUiBeforeNativeQuit(
  BuildContext context, {
  Duration frameTimeout = const Duration(seconds: 2),
}) async {
  if (!context.mounted) return;
  FocusManager.instance.primaryFocus?.unfocus();
  Tooltip.dismissAllToolTips();
  ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
  Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
  try {
    await waitForUiFrame(timeout: frameTimeout);
  } on TimeoutException catch (error) {
    // Opslaan en netwerkopruiming zijn al voltooid. Een geminimaliseerd
    // venster mag het afsluiten niet alsnog onbeperkt tegenhouden.
    logWarning('Afsluiten: geen frame voor UI-opruiming', error);
  }
  await Future<void>.delayed(Duration.zero);
}
