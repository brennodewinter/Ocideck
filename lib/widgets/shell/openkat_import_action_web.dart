// De webhelft van de OpenKAT-import (#767): een lege romp. Het menu-item
// bestaat op web niet (de scanner leest een map van schijf), dus dit wordt
// nooit aangeroepen — maar de namen moeten bestaan om te compileren zonder
// dart:io de webbundel in te trekken.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';

Future<void> importOpenKatReports(
  BuildContext context,
  WidgetRef ref, {
  String? directoryOverride,
}) async {}

/// Webromp; het menu-item bestaat daar niet.
String openKatLabel(AppLocalizations l10n) => '';
