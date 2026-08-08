import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/markdown_kind.dart';
import '../../services/file_service.dart';
import '../../state/deck_provider.dart' show fileServiceProvider;
import '../../state/document_provider.dart';
import '../../state/settings_provider.dart'
    show settingsProvider, SettingsTraces;

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
Future<bool> saveDocumentWithDestination(
  BuildContext context,
  WidgetRef ref,
  DocumentNotifier notifier,
) async {
  final state = notifier.currentState;
  final document = state.document;
  if (document == null) return false;

  final path = state.filePath;
  if (path != null) {
    // Nothing changed since the last save → already on disk, byte-identical.
    if (!state.isDirty) return true;
    if (await saveDocument(document, path)) {
      notifier.markSaved(filePath: path);
      return true;
    }
    // Writing to the existing path failed (read-only, moved, no permission):
    // don't dead-end — fall through to "Save as…" so a copy can still be kept.
  }

  // No path yet (a new document) or the path-save failed: "Save as…" keeps the
  // work as a copy rather than losing it.
  final saved = await ref.read(fileServiceProvider).saveDocumentAs(document);
  if (saved == null) return false;
  notifier.markSaved(filePath: saved);
  await ref
      .read(settingsProvider.notifier)
      .addRecentFile(saved, kind: MarkdownKind.document);
  return true;
}
