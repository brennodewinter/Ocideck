import 'package:flutter/material.dart';
import '../../models/slide.dart';
import '../../l10n/app_localizations.dart';

class FreeMarkdownEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;

  const FreeMarkdownEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
  });

  @override
  State<FreeMarkdownEditor> createState() => _FreeMarkdownEditorState();
}

class _FreeMarkdownEditorState extends State<FreeMarkdownEditor> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.slide.customMarkdown);
    _ctrl.addListener(_emit);
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d('Markdown inhoud'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: TextField(
              controller: _ctrl,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                hintText: l10n.d('# Slide\n\nInhoud hier...'),
                alignLabelWithHint: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
