import 'package:flutter/material.dart';
import '../../models/slide.dart';
import '_editor_field.dart';

class SectionEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;

  const SectionEditor({super.key, required this.slide, required this.onUpdate});

  @override
  State<SectionEditor> createState() => _SectionEditorState();
}

class _SectionEditorState extends State<SectionEditor> {
  late final TextEditingController _title;
  late final TextEditingController _subtitle;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.slide.title);
    _subtitle = TextEditingController(text: widget.slide.subtitle);
    _title.addListener(_emit);
    _subtitle.addListener(_emit);
  }

  void _emit() {
    widget.onUpdate(
      widget.slide.copyWith(title: _title.text, subtitle: _subtitle.text),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return EditorFieldList(
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
