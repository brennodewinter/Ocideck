part of '../app_shell.dart';

/// Bouwt tijdelijke Flutter-oppervlakken af voordat het native venster sluit.
///
/// Een oorspronkelijke macOS-close vernietigt de renderboom onmiddellijk. Als
/// er dan nog een exportdialoog, tooltipanimatie of scrollpositie aan hangt,
/// krijgen die geen normaal dispose-frame meer en volgen assertions uit de
/// semantics- en tickerlagen. Eerst terug naar de wortelroute en één frame
/// laten landen geeft elk tijdelijk oppervlak zijn gewone afbouwpad.
@visibleForTesting
Future<void> settleUiBeforeNativeQuit(BuildContext context) async {
  if (!context.mounted) return;
  FocusManager.instance.primaryFocus?.unfocus();
  Tooltip.dismissAllToolTips();
  ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
  Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
  WidgetsBinding.instance.ensureVisualUpdate();
  await WidgetsBinding.instance.endOfFrame;
  await Future<void>.delayed(Duration.zero);
}
