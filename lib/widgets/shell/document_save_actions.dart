import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/markdown_document.dart';
import '../../models/markdown_kind.dart';
import '../../services/document_integrity.dart';
import '../../services/file_service.dart';
import '../../state/deck_provider.dart' show fileServiceProvider;
import '../../state/document_provider.dart';
import '../../state/tabs_provider.dart'
    show ImportSecurityAlarm, importSecurityAlarmProvider;
import '../../state/settings_provider.dart'
    show settingsProvider, SettingsTraces;
import '../../utils/document_front_matter.dart';
import '../../utils/error_snackbar.dart';
import '../../utils/markdown_paste_cleanup.dart';
import '../../utils/markdown_quill_codec.dart';
import '../../utils/source_patcher.dart';
import '../dialogs/document_conflict_dialog.dart';
import 'open_failure_message.dart';

/// Saves the document held by [notifier], the single way every save route lands:
/// the app-wide Ctrl/Cmd+S, the document editor's own shortcut, and save-on-quit.
///
/// This is the document counterpart of `saveDeckWithDestination`. Before it, the
/// app-wide Ctrl/Cmd+S only knew how to save a **deck**, so pressing it on a
/// document tab did nothing useful — and in the visual (WYSIWYG) mode, where the
/// editor's own shortcut never receives the keystroke, a document could not be
/// saved at all. Routing every save through here makes the shortcut behave
/// identically in Visueel and Bron, just like the presentation side.
///
/// Byte-faithful back to its path when it has one; otherwise "Save as…" picks a
/// destination (keeping a copy of work that was never saved) and the file is
/// remembered in the recent list. Returns `false` when nothing was written —
/// the picker was cancelled or the write failed — so save-on-quit can hold.
///
/// When the document was edited in Visueel, the source in the notifier is the
/// Quill → Markdown round-trip — not byte-faithful to what was on disk. In that
/// case, we patch the user's actual edits onto the original source instead of
/// overwriting it with the normalized round-trip (#1613).
Future<bool> saveDocumentWithDestination(
  BuildContext context,
  WidgetRef ref,
  DocumentNotifier notifier,
) async {
  final state = notifier.currentState;
  final document = state.document;
  if (document == null) return false;

  // Als de bewerking uit Visueel kwam, is document.source de genormaliseerde
  // round-trip — niet byte-getrouw aan wat op schijf stond. We patchen de
  // echte bewerkingen op de originele bron (savedSource) in plaats van de
  // hele genormaliseerde bron weg te schrijven (#1613).
  final documentToSave = state.visualEdited && state.savedSource != null
      ? _patchVisualSave(document, state.savedSource!)
      : document;

  final path = state.filePath;
  if (path != null) {
    // Nothing changed since the last save → already on disk, byte-identical.
    if (!state.isDirty) return true;
    // Conflictcontrole: is het bestand buiten OciDeck gewijzigd? Vergelijk
    // de hash van wat nu op schijf staat met de hash die we bij laden of
    // opslaan onthielden (#1699, #1683).
    final diskHash = await _readFileHash(path);
    if (diskHash != null &&
        state.savedFileHash != null &&
        diskHash != state.savedFileHash) {
      if (!context.mounted) return false;
      final outcome = await _resolveDocumentConflict(
        context,
        ref,
        notifier,
        path,
        diskHash,
        documentToSave,
      );
      switch (outcome) {
        case _DocSaveOutcome.saved:
          return true;
        case _DocSaveOutcome.abort:
          return false;
        case _DocSaveOutcome.proceed:
          break; // overwrite: ga door met opslaan.
      }
    }
    final written = await saveDocument(documentToSave, path);
    if (written != null) {
      // Werk de notifier bij met de versie zoals die op schijf staat —
      // mem:-verwijzingen zijn inmiddels images/-paden — zodat editor,
      // schijf en conflict-hash over één bron lopen (#2120).
      if (written.source != document.source) {
        notifier.replaceSource(written.source);
      }
      notifier.markSaved(
        filePath: path,
        savedFileHash: DocumentIntegrity.hashDocument(written),
      );
      // Werk de recente-bestanden-lijst bij, net als bij openen en
      // Opslaan-als — een in-place save liet de lijst ongemoeid (#1676).
      await ref
          .read(settingsProvider.notifier)
          .addRecentFile(path, kind: MarkdownKind.document);
      return true;
    }
    // Writing to the existing path failed (read-only, moved, no permission):
    // don't dead-end — fall through to "Save as…" so a copy can still be kept.
  }

  // No path yet (a new document) or the path-save failed: "Save as…" keeps the
  // work as a copy rather than losing it.
  final saved = await ref
      .read(fileServiceProvider)
      .saveDocumentAs(documentToSave);
  if (saved == null) return false;
  await _adoptSavedDocument(
    ref,
    notifier,
    saved.path,
    saved.document,
    oldSource: document.source,
  );
  return true;
}

/// Neemt het zojuist gekozen schrijfpad over in de notifier: tabblad wijst
/// nu naar de kopie, is schoon en loopt qua bron, schijf en conflict-hash
/// gelijk. Ook gebruikt door "Mijn versie als kopie bewaren" (#2323).
Future<void> _adoptSavedDocument(
  WidgetRef ref,
  DocumentNotifier notifier,
  String path,
  MarkdownDocument saved, {
  required String oldSource,
}) async {
  if (saved.source != oldSource) {
    notifier.replaceSource(saved.source);
  }
  notifier.markSaved(
    filePath: path,
    savedFileHash: DocumentIntegrity.hashDocument(saved),
  );
  // Werk de recente-bestanden-lijst bij, net als bij openen en Opslaan-als.
  await ref
      .read(settingsProvider.notifier)
      .addRecentFile(path, kind: MarkdownKind.document);
}

/// Patcht de bewerkingen uit de visuele editor op de originele bron.
///
/// [savedSource] is de bron zoals die op schijf stond. De bron van [document] is
/// de genormaliseerde round-trip mét gebruikersbewerkingen. We berekenen de
/// baseline (round-trip zónder bewerkingen) via dezelfde weg als de visuele
/// editor — `normalizeRichTextMarkdown` → `documentFromMarkdown` →
/// `markdownFromDocument` — en diff'en die tegen die bron om de echte
/// bewerkingen te isoleren. Die diff toegepast op savedSource levert de
/// byte-getrouwe versie op.
///
/// Het resultaat komt uit [document] en niet uit een verse parse, zodat wat het
/// document naast zijn tekst meedraagt — de BOM-vlag — niet onderweg verdwijnt.
MarkdownDocument _patchVisualSave(
  MarkdownDocument document,
  String savedSource,
) {
  final currentSource = document.source;
  // De codec kent geen YAML-frontmatter: `theme: rvs\n---` parseert als een
  // setext-kop en de baseline vermangelt het blok, waarna de regel-diff het
  // frontmatter-verschil als een gebruikersbewerking midden in de body plant
  // (#2142). De visuele editor laadt alleen de body — dus de baseline hoort
  // óók alleen over de body te lopen, met het frontmatter-blok erbuiten.
  final savedSplit = splitDocumentFrontMatter(savedSource);
  final currSplit = splitDocumentFrontMatter(currentSource);
  final baseline = MarkdownQuillCodec.markdownFromDocument(
    MarkdownQuillCodec.documentFromMarkdown(
      normalizeRichTextMarkdown(savedSplit.body),
    ),
  );
  final patched = patchVisualEdits(
    original: savedSplit.body,
    baseline: baseline,
    current: currSplit.body,
  );
  // Neem het huidige blok terug, niet het opgeslagen: zo overleeft een
  // tussentijdse stijl-/TLP-wijziging de opslag.
  return document.withSource(currSplit.block + patched);
}

/// Wat de conflictlus teruggeeft aan [saveDocumentWithDestination].
enum _DocSaveOutcome { proceed, saved, abort }

/// De keuzes uit de conflict-dialoog (#1699, #2323).
enum _ConflictChoice { cancel, reload, overwrite, saveCopy, compare }

/// Wat de vergelijkingsdialoog aanvraagt — terug is geen keuze maar een
/// terugkeer naar de eerste dialoog.
enum _DocConflictAction { back, action }

/// De lus rond het lokale documentconflict (#2323): de eerste dialoog biedt
/// naast de bestaande keuzes "Verschillen bekijken…" en "Mijn versie als
/// kopie bewaren". De vergelijking leest de schijfversie door dezelfde
/// open-poort als elk openen; vóór élke schrijfactie wordt de hash opnieuw
/// gecontroleerd zodat een tussentijdse wijziging nooit stilletjes wordt
/// overschreven.
Future<_DocSaveOutcome> _resolveDocumentConflict(
  BuildContext context,
  WidgetRef ref,
  DocumentNotifier notifier,
  String path,
  String fingerprint,
  MarkdownDocument documentToSave,
) async {
  for (;;) {
    if (!context.mounted) return _DocSaveOutcome.abort;
    var choice = await _showConflictDialog(context);
    if (!context.mounted) return _DocSaveOutcome.abort;
    if (choice == _ConflictChoice.compare) {
      final compare = await _compareDocumentConflict(
        context,
        ref,
        path,
        fingerprint,
        documentToSave,
      );
      fingerprint = compare.fingerprint;
      if (compare.action == null) return _DocSaveOutcome.abort;
      if (compare.action == _DocConflictAction.back) continue;
      choice = compare.choice;
    }
    switch (choice) {
      case _ConflictChoice.cancel:
      case _ConflictChoice.compare:
        return _DocSaveOutcome.abort;
      case _ConflictChoice.reload:
        if (!context.mounted) return _DocSaveOutcome.abort;
        await _reloadFromDisk(context, ref, notifier, path);
        return _DocSaveOutcome.abort;
      case _ConflictChoice.saveCopy:
        final saved = await ref
            .read(fileServiceProvider)
            .saveDocumentAs(documentToSave);
        if (saved == null) return _DocSaveOutcome.abort;
        if (!context.mounted) return _DocSaveOutcome.abort;
        await _adoptSavedDocument(
          ref,
          notifier,
          saved.path,
          saved.document,
          oldSource: documentToSave.source,
        );
        return _DocSaveOutcome.saved;
      case _ConflictChoice.overwrite:
        final now = await _readFileHash(path);
        if (now != fingerprint) {
          // Verlopen vingerafdruk: niet schrijven — de melding zegt waarom en
          // de lus geeft de keuze met de verse stand opnieuw.
          fingerprint = now ?? fingerprint;
          if (!context.mounted) return _DocSaveOutcome.abort;
          showErrorSnackBar(
            ScaffoldMessenger.of(context),
            context.l10n,
            context.l10n.d(
              'Het bestand is ondertussen opnieuw gewijzigd; vergelijk opnieuw.',
            ),
          );
          continue;
        }
        return _DocSaveOutcome.proceed;
    }
  }
}

/// Leest de schijfversie door de open-poort en toont de blokvergelijking.
/// Schrijft nooit tijdens de analyse; geeft de gevraagde actie terug plus de
/// vingerafdruk van de geanalyseerde versie.
Future<
  ({_DocConflictAction? action, _ConflictChoice choice, String fingerprint})
>
_compareDocumentConflict(
  BuildContext context,
  WidgetRef ref,
  String path,
  String fingerprint,
  MarkdownDocument documentToSave,
) async {
  final files = ref.read(fileServiceProvider);
  final result = await files.openDocumentDetailed(path);
  if (!context.mounted) {
    return (
      action: _DocConflictAction.back,
      choice: _ConflictChoice.cancel,
      fingerprint: fingerprint,
    );
  }
  final disk = result.document;
  if (disk == null) {
    if (result.failure == OpenFailure.unsafe) {
      final findings = await files.scanForUnsafeMarkdown(path);
      ref.read(importSecurityAlarmProvider.notifier).state =
          ImportSecurityAlarm(path: path, findings: findings);
    } else {
      showErrorSnackBar(
        ScaffoldMessenger.of(context),
        context.l10n,
        openFailureMessage(context.l10n, result.failure),
      );
    }
    return (
      action: _DocConflictAction.back,
      choice: _ConflictChoice.cancel,
      fingerprint: fingerprint,
    );
  }
  final analysisHash = await _readFileHash(path) ?? fingerprint;
  if (!context.mounted) {
    return (
      action: _DocConflictAction.back,
      choice: _ConflictChoice.cancel,
      fingerprint: analysisHash,
    );
  }
  final action = await DocumentConflictDialog.show(
    context,
    ours: documentToSave.source,
    theirs: disk.source,
  );
  final choice = switch (action) {
    DocumentConflictAction.overwrite => _ConflictChoice.overwrite,
    DocumentConflictAction.loadDisk => _ConflictChoice.reload,
    DocumentConflictAction.saveCopy => _ConflictChoice.saveCopy,
    _ => _ConflictChoice.cancel,
  };
  return (
    action: action == DocumentConflictAction.back || action == null
        ? _DocConflictAction.back
        : _DocConflictAction.action,
    choice: choice,
    fingerprint: analysisHash,
  );
}

/// Leest het bestand op [path] en retourneert de SHA-512-hash van de bytes,
/// of `null` als het bestand niet (meer) bestaat of niet leesbaar is.
Future<String?> _readFileHash(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    return DocumentIntegrity.hashBytes(bytes);
  } on FileSystemException {
    return null;
  }
}

/// Toont de conflict-dialoog: het bestand is buiten OciDeck gewijzigd.
/// De gebruiker kiest tussen de verschillen bekijken, Herladen (opnieuw
/// inladen), Overschrijven (toch opslaan), de eigen versie als kopie
/// bewaren, of Annuleren (#1699, #2323).
Future<_ConflictChoice> _showConflictDialog(BuildContext context) async {
  final l10n = context.l10n;
  final choice = await showDialog<_ConflictChoice>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      content: Text(
        l10n.d('Het bestand is gewijzigd door een ander programma.'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, _ConflictChoice.cancel),
          child: Text(l10n.d('Annuleren')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, _ConflictChoice.compare),
          child: Text(l10n.d('Verschillen bekijken…')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, _ConflictChoice.reload),
          child: Text(l10n.d('Herladen')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, _ConflictChoice.saveCopy),
          child: Text(l10n.d('Mijn versie als kopie bewaren')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, _ConflictChoice.overwrite),
          child: Text(l10n.d('Overschrijven')),
        ),
      ],
    ),
  );
  return choice ?? _ConflictChoice.cancel;
}

/// Herlaadt het document van schijf en laadt het in de notifier.
///
/// Loopt door dezelfde poort als elk ander openen ([FileService.openDocumentDetailed]):
/// grootte-cap, UTF-8-decodering, veiligheidsscan en BOM-vlag. Hier stond een
/// eigen `String.fromCharCodes(bytes)`, dat elke UTF-8-byte als een los teken las
/// (een `é` werd `Ã©`, een BOM werd `ï»¿`) en de scan oversloeg.
///
/// Weigert de poort het bestand, dan blijft de notifier ongemoeid — maar dat mag
/// niet stil: wie op "Herladen" tikt en niets ziet gebeuren, zit vast. Een
/// onveilig bestand zet het veiligheidsalarm, net als bij het openen van een
/// tabblad; elke andere weigering krijgt dezelfde woorden als een gewone open.
Future<void> _reloadFromDisk(
  BuildContext context,
  WidgetRef ref,
  DocumentNotifier notifier,
  String path,
) async {
  final files = ref.read(fileServiceProvider);
  final result = await files.openDocumentDetailed(path);
  final doc = result.document;
  if (doc != null) {
    notifier.loadDocument(doc, filePath: path);
    return;
  }
  if (result.failure == OpenFailure.unsafe) {
    final findings = await files.scanForUnsafeMarkdown(path);
    ref.read(importSecurityAlarmProvider.notifier).state = ImportSecurityAlarm(
      path: path,
      findings: findings,
    );
    return;
  }
  if (!context.mounted) return;
  showErrorSnackBar(
    ScaffoldMessenger.of(context),
    context.l10n,
    openFailureMessage(context.l10n, result.failure),
  );
}
