import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/slide.dart';

class ListStyleSelector extends StatelessWidget {
  final ListStyle value;
  final ValueChanged<ListStyle> onChanged;

  const ListStyleSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SegmentedButton<ListStyle>(
      segments: [
        ButtonSegment(
          value: ListStyle.bullets,
          icon: const Icon(Icons.format_list_bulleted, size: 18),
          label: Text(l10n.d('Opsomming')),
        ),
        ButtonSegment(
          value: ListStyle.numbered,
          icon: const Icon(Icons.format_list_numbered, size: 18),
          label: Text(l10n.d('Nummering')),
        ),
        ButtonSegment(
          value: ListStyle.checklist,
          icon: const Icon(Icons.checklist, size: 18),
          label: Text(l10n.d('Checklist')),
        ),
        ButtonSegment(
          value: ListStyle.richText,
          icon: const Icon(Icons.text_fields, size: 18),
          label: Text(l10n.d('Teksteditor')),
        ),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}
