import 'package:flutter/material.dart';
import '../../models/slide.dart';
import '_editor_field.dart';

class SectionEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final bool nestedInScrollView;

  const SectionEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.nestedInScrollView = false,
  });

  @override
  State<SectionEditor> createState() => _SectionEditorState();
}

class _SectionEditorState extends State<SectionEditor>
    with EditorTextControllers {
  late final TextEditingController _title;
  late final TextEditingController _subtitle;

  @override
  void initState() {
    super.initState();
    _title = newController(widget.slide.title, _emit);
    _subtitle = newController(widget.slide.subtitle, _emit);
  }

  void _emit() {
    widget.onUpdate(
      widget.slide.copyWith(title: _title.text, subtitle: _subtitle.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    return EditorFieldList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        EditorField(
          label: 'Tussentitel (H1)',
          controller: _title,
          hint: 'Sectienaam',
          maxLines: 2,
        ),
        EditorField(
          label: 'Ondertitel / toelichting',
          controller: _subtitle,
          hint: 'Optionele toelichting',
          maxLines: 3,
        ),
      ],
    );
  }
}
