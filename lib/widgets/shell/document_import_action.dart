// Document-import-actie: kiest een .docx of .odt, zet het om naar Markdown,
// en opent het resultaat als een nieuw document-tabblad.
//
// Lichter dan de presentatie-import (presentation_import_action.dart): een
// document kent geen dia's en geen probleemdia's. Wat het sinds #2119 wél
// kent is de huisstijl van de bron: draagt het document letters, kleuren, een
// logo op elke bladzijde of een voettekst, dan vraagt één dialoog of die als
// stijl overgenomen wordt — nieuw, of als een profiel dat er al is. De
// fail-closed safety-scan zit in de service (document_import_service.dart),
// niet hier — dezelfde plek als bij het openen van een vreemd `.md`.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/settings.dart';
import '../../services/file_service.dart' hide ImportFailure;
import '../../services/import/document_import_service.dart';
import '../../services/import/imported_document_profile.dart';
import '../../services/import/models/source_document_style.dart';
import '../../services/style_logo_lookup.dart';
import '../../services/web_asset_store.dart';
import '../../state/deck_provider.dart' show fileServiceProvider;
import '../../state/settings_provider.dart';
import '../../state/tabs_provider.dart';
import '../../utils/document_front_matter.dart';
import '../../utils/error_snackbar.dart';
import '../../utils/file_extension.dart';
import '../../utils/log.dart';
import '../dialogs/import_document_style_dialog.dart';

/// Importeert een `.docx` of `.odt` als een nieuw Markdown-document: kiest een
/// bestand, zet het om, vraagt zo nodig naar de huisstijl, en opent het
/// resultaat in een nieuw tabblad.
///
/// Leest de providers zelf via de container (zoals `app_shell_menu.dart`),
/// zodat de aanroepers — het welkomstscherm, de documenttoolbar — geen `ref`
/// hoeven door te geven. [fileOverride] slaat de bestandskiezer over; dat is
/// de testroute, net als bij de presentatie-import.
Future<void> importDocument(
  BuildContext context, {
  ({Uint8List bytes, String name})? fileOverride,
}) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context);

  final picked =
      fileOverride ??
      await _pickDocument(
        l10n,
        initialDirectory: container.read(settingsProvider).homeDirectory,
      );
  if (picked == null || !context.mounted) return;

  final result = importDocumentBytes(picked.bytes, filename: picked.name);
  if (!context.mounted) return;

  if (!result.isSuccess) {
    final failure = result.failure!;
    logWarning('importDocument: ${failure.message}', failure.cause);
    showErrorSnackBar(messenger, l10n, failure.message);
    return;
  }

  var markdown = result.markdown!;
  if (result.style.isNotEmpty) {
    final styleName = await _resolveDocumentStyle(
      context,
      container,
      result.style,
      fallbackName: _documentTitle(markdown) ?? stemOfFileName(picked.name),
    );
    if (!context.mounted) return;
    if (styleName != null) {
      markdown = withDocumentStyleName(markdown, styleName);
    }
  }

  container.read(tabsProvider.notifier).newDocumentFromMarkdown(markdown);
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        _notImportedSummary(l10n, result.notImported) ??
            l10n.d('Document geïmporteerd.'),
      ),
    ),
  );
}

/// De eerste kop van het document, als suggestie voor de stijlnaam. De
/// importeur escapet Markdown-tekens (`\_`, `\#`); in een naam horen die
/// backslashes niet.
String? _documentTitle(String markdown) {
  for (final line in markdown.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('# ')) {
      final title = trimmed
          .substring(2)
          .replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!)
          .trim();
      if (title.isNotEmpty) return title;
    }
  }
  return null;
}

/// Vraagt wat er met de huisstijl gebeurt en levert de naam van het profiel
/// dat het document krijgt — of `null` voor alleen tekst.
Future<String?> _resolveDocumentStyle(
  BuildContext context,
  ProviderContainer container,
  SourceDocumentStyle style, {
  required String fallbackName,
}) async {
  final settings = container.read(settingsProvider);
  final logo = style.logoCandidates.firstOrNull;
  final existing = await _matchingProfile(settings.themeProfiles, style, logo);
  if (!context.mounted) return null;

  final choice = await ImportDocumentStyleDialog.ask(
    context,
    style: style,
    suggestedStyleName: context.l10n
        .d('Stijl van {naam}')
        .replaceAll('{naam}', fallbackName),
    existingStyleName: existing?.name,
    logoIsSessionOnly: kIsWeb,
  );
  if (!context.mounted) return null;

  switch (choice.disposition) {
    case ImportDocumentStyleDisposition.textOnly:
      return null;
    case ImportDocumentStyleDisposition.useExisting:
      return existing?.name;
    case ImportDocumentStyleDisposition.newStyle:
      final name = choice.styleName.isEmpty
          ? context.l10n
                .d('Stijl van {naam}')
                .replaceAll('{naam}', fallbackName)
          : choice.styleName;
      String? logoPath;
      if (choice.includeLogo && logo != null) {
        logoPath = await _placeLogo(context, container, logo, name);
        if (!context.mounted) return null;
      }
      final profile = buildImportedDocumentProfile(
        style: style,
        base: settings.themeProfile,
        name: name,
        logoPath: logoPath,
        logo: logoPath == null ? null : logo,
      );
      final added = await addThemeProfileWithoutSelection(
        container.read(settingsProvider.notifier),
        profile,
      );
      return added.name;
  }
}

/// Het profiel dat deze huisstijl al is: dezelfde letters, kleuren en banden,
/// én hetzelfde logo (op de bytes) — of allebei geen logo.
Future<ThemeProfile?> _matchingProfile(
  List<ThemeProfile> profiles,
  SourceDocumentStyle style,
  DocumentLogoCandidate? logo,
) async {
  final byHash = await styleProfilesByLogoHash(
    profiles,
    pathOf: (profile) => profile.effectiveDocumentLogoPath,
  );
  for (final profile in profiles) {
    if (!documentStyleMatchesProfile(style, profile)) continue;
    final path = profile.effectiveDocumentLogoPath?.trim() ?? '';
    if (logo == null) {
      if (path.isEmpty) return profile;
      continue;
    }
    if (identical(byHash[logo.sha256], profile)) return profile;
  }
  return null;
}

/// Hoe een logo blijvend wordt weggeschreven. Onder `flutter test` hangt de
/// app-supportmap van `path_provider` op de fake-async-klok (het antwoord
/// van het platform komt nooit), dus een widget-test zet hier een schrijver
/// neer die in het geheugen blijft — dezelfde reden als
/// `debugImportTaskRunner` bij de presentatie-import.
@visibleForTesting
Future<String?> Function(Uint8List bytes, {required String profileName})?
debugImportedDocumentLogoWriter;

/// Zet het logo blijvend neer (desktop) of in de webopslag; valt bij een
/// mislukte schrijfactie terug op de webopslag mét melding, zodat de stijl er
/// in elk geval voor deze sessie is.
Future<String> _placeLogo(
  BuildContext context,
  ProviderContainer container,
  DocumentLogoCandidate logo,
  String profileName,
) async {
  final writer =
      debugImportedDocumentLogoWriter ??
      container.read(fileServiceProvider).materializeImportedStyleLogo;
  final durable = kIsWeb
      ? null
      : await writer(logo.bytes, profileName: profileName);
  if (durable != null) return durable;
  if (!kIsWeb && context.mounted) {
    showErrorSnackBar(
      ScaffoldMessenger.of(context),
      context.l10n,
      context.l10n.d(
        'Het logo kon niet blijvend worden bewaard; het blijft alleen deze sessie beschikbaar.',
      ),
    );
  }
  return WebAssetStore.put(logo.bytes, name: logo.name ?? 'logo.${logo.ext}');
}

/// De "niet overgenomen"-bijlage bij de succesmelding: wat er in het
/// brondocument stond maar niet meekwam, geteld per soort (#2120). `null`
/// als alles mee is — dan blijft de gewone succesmelding staan.
String? _notImportedSummary(AppLocalizations l10n, List<String> kinds) {
  if (kinds.isEmpty) return null;
  const names = {
    'afbeelding': ('{n} afbeelding', '{n} afbeeldingen'),
    'tekstkader': ('{n} tekstkader', '{n} tekstkaders'),
    'groep': ('{n} groep', '{n} groepen'),
    'object': ('{n} object', '{n} objecten'),
  };
  final counts = <String, int>{};
  for (final kind in kinds) {
    counts[kind] = (counts[kind] ?? 0) + 1;
  }
  final parts = [
    for (final entry in counts.entries)
      if (names[entry.key] case final pair?)
        l10n
            .d(entry.value == 1 ? pair.$1 : pair.$2)
            .replaceAll('{n}', '${entry.value}'),
  ];
  if (parts.isEmpty) return null;
  return l10n
      .d('Document geïmporteerd — niet overgenomen: {lijst}')
      .replaceAll('{lijst}', parts.join(', '));
}

/// De bestandskiezer, apart gehouden zodat de import zelf één rechte lijn
/// blijft. `null` betekent: niets gekozen.
Future<({Uint8List bytes, String name})?> _pickDocument(
  AppLocalizations l10n, {
  String? initialDirectory,
}) async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: documentImportExtensions,
    dialogTitle: l10n.d('Document kiezen'),
    initialDirectory: initialDirectory,
  );
  if (picked.isEmpty) return null;
  final file = picked.first;
  return (bytes: Uint8List.fromList(await file.readAsBytes()), name: file.name);
}

/// Het menulabel voor de document-import.
String documentImportLabel(AppLocalizations l10n) =>
    l10n.d('Document importeren…');
