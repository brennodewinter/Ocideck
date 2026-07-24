// De webhelft van de OpenKAT-import (#767): een lege romp. Het menu-item
// bestaat op web niet (de scanner leest een map van schijf), dus dit wordt
// nooit aangeroepen — maar de namen moeten bestaan om te compileren zonder
// dart:io de webbundel in te trekken.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'openkat_import_summary.dart';

/// Webromp: er is niets geprobeerd, dus `null` — zie de desktophelft.
Future<OpenKatImportOutcome?> importOpenKatReports(
  BuildContext context,
  WidgetRef ref, {
  String? directoryOverride,
  bool announce = true,
}) async => null;

/// Webromp; het menu-item bestaat daar niet.
String openKatLabel(AppLocalizations l10n) => '';
