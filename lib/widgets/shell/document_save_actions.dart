import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/markdown_document.dart';
import '../../models/markdown_kind.dart';
import '../../services/document_integrity.dart';
import '../../services/file_service.dart';
import '../../state/deck_provider.dart' show fileServiceProvider;
import '../../state/document_provider.dart';
import '../../state/settings_provider.dart'
    show settingsProvider, SettingsTraces;
import '../../utils/markdown_paste_cleanup.dart';
import '../../utils/markdown_quill_codec.dart';
import '../../utils/source_patcher.dart';

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
      ? _patchVisualSave(state.savedSource!, document.source)
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
      final choice = await _showConflictDialog(context);
      if (choice == _ConflictChoice.cancel) return false;
      if (choice == _ConflictChoice.reload) {
        await _reloadFromDisk(notifier, path);
        return false;
      }
      // overwrite: ga door met opslaan.
    }
    if (await saveDocument(documentToSave, path)) {
      // Werk de notifier bij met de byte-getrouwe versie, zodat de editor
      // en de notifier dezelfde bron zien — geen drift meer.
      if (documentToSave != document) {
        notifier.replaceSource(documentToSave.source);
      }
      notifier.markSaved(
        filePath: path,
        savedFileHash: DocumentIntegrity.hashMarkdown(documentToSave.source),
      );
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
  if (documentToSave != document) {
    notifier.replaceSource(documentToSave.source);
  }
  notifier.markSaved(
    filePath: saved,
    savedFileHash: DocumentIntegrity.hashMarkdown(documentToSave.source),
  );
  await ref
      .read(settingsProvider.notifier)
      .addRecentFile(saved, kind: MarkdownKind.document);
  return true;
}

/// Patcht de bewerkingen uit de visuele editor op de originele bron.
///
/// [savedSource] is de bron zoals die op schijf stond. [currentSource] is de
/// genormaliseerde round-trip mét gebruikersbewerkingen. We berekenen de
/// baseline (round-trip zónder bewerkingen) via dezelfde weg als de visuele
/// editor — `normalizeRichTextMarkdown` → `documentFromMarkdown` →
/// `markdownFromDocument` — en diff'en die tegen currentSource om de echte
/// bewerkingen te isoleren. Die diff toegepast op savedSource levert de
/// byte-getrouwe versie op.
MarkdownDocument _patchVisualSave(String savedSource, String currentSource) {
  final baseline = MarkdownQuillCodec.markdownFromDocument(
    MarkdownQuillCodec.documentFromMarkdown(
      normalizeRichTextMarkdown(savedSource),
    ),
  );
  final patched = patchVisualEdits(
    original: savedSource,
    baseline: baseline,
    current: currentSource,
  );
  return MarkdownDocument.parse(patched);
}

/// De keuzes uit de conflict-dialoog (#1699).
enum _ConflictChoice { cancel, reload, overwrite }

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
/// De gebruiker kiest tussen Herladen (opnieuw inladen), Overschrijven
/// (toch opslaan) of Annuleren.
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
          onPressed: () => Navigator.pop(ctx, _ConflictChoice.reload),
          child: Text(l10n.d('Herladen')),
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
Future<void> _reloadFromDisk(DocumentNotifier notifier, String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    final source = String.fromCharCodes(bytes);
    final doc = MarkdownDocument.parse(source);
    notifier.loadDocument(doc, filePath: path);
  } on FileSystemException {
    // Bestand verdween — laat de notifier ongemoeid.
  }
}
