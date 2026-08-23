import 'package:material_ui/material_ui.dart';
import '../../models/slide.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'editor_text_controller.dart';

class FreeMarkdownEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final bool nestedInScrollView;

  const FreeMarkdownEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.nestedInScrollView = false,
  });

  @override
  State<FreeMarkdownEditor> createState() => _FreeMarkdownEditorState();
}

class _FreeMarkdownEditorState extends State<FreeMarkdownEditor> {
  late final EditorTextController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = EditorTextController(text: widget.slide.customMarkdown);
    _ctrl.addTextListener(_emit);
  }

  void _emit() {
    widget.onUpdate(widget.slide.copyWith(customMarkdown: _ctrl.text));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final field = TextField(
      controller: _ctrl,
      maxLines: widget.nestedInScrollView ? 16 : null,
      minLines: widget.nestedInScrollView ? 8 : null,
      expands: !widget.nestedInScrollView,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      decoration: InputDecoration(
        hintText: l10n.d('# Slide\n\nInhoud hier...'),
        alignLabelWithHint: true,
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d('Markdown inhoud'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate500,
            ),
          ),
          const SizedBox(height: 6),
          if (widget.nestedInScrollView) field else Expanded(child: field),
        ],
      ),
    );
  }
}
