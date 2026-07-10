import 'package:flutter/material.dart';
import '../../models/slide.dart';
import '_editor_field.dart';

/// Placeholder editor for the Informatieveiligheid slide types (P1-S scaffold):
/// `finding`, `findingsSummary`, `checklist`, `scopeMatrix`, `signOff`.
///
/// Their body is authored as free Markdown in [Slide.customMarkdown] and
/// round-trips like a free-Markdown slide — the `_class` token carries the type
/// (see `markdown_service`/`_inferSlideType`). Each type's structured editor
/// replaces this registration in P1-FIND/CHK/SCOPE/SUM/SIGN; until then this
/// keeps the type authorable and the guard test green.
class ScaffoldSlideEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final bool nestedInScrollView;

  const ScaffoldSlideEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.nestedInScrollView = false,
  });

  @override
  State<ScaffoldSlideEditor> createState() => _ScaffoldSlideEditorState();
}

class _ScaffoldSlideEditorState extends State<ScaffoldSlideEditor>
    with EditorTextControllers {
  late final TextEditingController _body;

  @override
  void initState() {
    super.initState();
    _body = newController(widget.slide.customMarkdown, _emit);
  }

  void _emit() {
    widget.onUpdate(widget.slide.copyWith(customMarkdown: _body.text));
  }

  @override
  Widget build(BuildContext context) {
    return EditorFieldList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [EditorField(label: 'Inhoud', controller: _body, maxLines: 16)],
    );
  }
}
