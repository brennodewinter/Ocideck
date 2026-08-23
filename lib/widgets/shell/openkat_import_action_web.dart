// De webhelft van de OpenKAT-import (#767): een lege romp. Het menu-item
// bestaat op web niet (de scanner leest een map van schijf), dus dit wordt
// nooit aangeroepen — maar de namen moeten bestaan om te compileren zonder
// dart:io de webbundel in te trekken.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/deck.dart';
import 'openkat_import_summary.dart';

/// Webromp: er is niets geprobeerd, dus `null` — zie de desktophelft.
Future<OpenKatImportOutcome?> importOpenKatReports(
  BuildContext context,
  WidgetRef ref, {
  String? directoryOverride,
  bool announce = true,
}) async => null;

/// Webromp; het menu-item bestaat daar niet.
String openKatLabel(AppLocalizations l10n, {bool updating = false}) => '';

bool isOpenKatGeneratedDeck(Deck deck) => false;

bool hasActiveOpenKatReport(WidgetRef ref) => false;

Future<void> showOpenKatInstallationWizard(BuildContext context) async {}

Future<void> showOpenKatServerReportDialog(BuildContext context) async {}
