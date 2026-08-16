// Het zichtbare label van een paginamaat.
//
// `PageSizeSpec` woont in lib/models/ en mag geen interface-afhankelijkheid
// dragen (zie modelUiImportBaseline in tool/check_conventions.dart), dus kan het
// zelf geen vertaling opzoeken. De maatnaam is taalneutraal ("A4"); alleen de
// oriëntatie is een wóórd. Die combinatie hoort op één plek te staan, want het
// label komt op twee plekken op het scherm: de paginamaat-dropdown in de
// instellingen en de indicator in de documenteditor.

import '../models/page_size.dart';
import 'app_localizations.dart';

/// Het label van [spec] in de taal van [l10n] — `"A4"` staand, `"A4 (liggend)"`
/// liggend.
String pageSizeLabel(AppLocalizations l10n, PageSizeSpec spec) => spec.landscape
    ? l10n.d('{maat} (liggend)').replaceAll('{maat}', spec.sizeName)
    : spec.sizeName;
