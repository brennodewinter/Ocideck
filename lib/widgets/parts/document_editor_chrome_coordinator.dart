part of '../document_editor_screen.dart';

/// Bundelt afgeleid volledig-documentwerk buiten de native tekstcallback.
class _DocumentEditorChromeCoordinator {
  _DocumentEditorChromeCoordinator(this.owner, DocumentState initial)
    : historyAvailability = ValueNotifier((initial.canUndo, initial.canRedo));

  static const _delay = Duration(milliseconds: 160);

  final _DocumentEditorScreenState owner;
  final ValueNotifier<(bool, bool)> historyAvailability;
  Timer? _timer;
  String? _visualPlain;
  int _visualOffset = 0;

  void schedule() {
    _timer?.cancel();
    _timer = Timer(_delay, _refresh);
  }

  void recordVisualCaret(String plain, int offset) {
    owner._visualCaret = offset;
    _visualPlain = plain;
    _visualOffset = offset;
    schedule();
  }

  void updateHistory() {
    final state = owner.ref.read(documentProvider);
    final next = (state.canUndo, state.canRedo);
    if (historyAvailability.value != next) historyAvailability.value = next;
  }

  void _refresh() {
    if (!owner.mounted) return;
    final plain = _visualPlain;
    if (owner._viewMode == _DocViewMode.visual &&
        owner._visualEditorKey.currentState != null &&
        plain != null) {
      owner._applyVisualCaretToChrome(plain, _visualOffset);
    } else {
      owner._syncOutlineToMarkdownCaret();
    }
    // Quill tekent iedere letter direct; statistieken, overzicht en
    // pagina-einden volgen één keer zodra de invoer kort tot rust komt.
    if (owner.mounted) owner._refreshChrome();
  }

  void dispose() {
    _timer?.cancel();
    historyAvailability.dispose();
  }
}
