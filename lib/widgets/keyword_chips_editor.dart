import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';

/// Trefwoorden als chips op een komma-gescheiden tekst.
///
/// [controller] blijft de bron: opslaan leest die tekst, niet een eigen lijst.
/// Enter of een komma voegt een chip toe; het kruisje haalt hem weg (#2395).
class KeywordChipsEditor extends StatefulWidget {
  const KeywordChipsEditor({
    super.key,
    required this.controller,
    this.enabled = true,
  });

  final TextEditingController controller;
  final bool enabled;

  @override
  State<KeywordChipsEditor> createState() => _KeywordChipsEditorState();
}

class _KeywordChipsEditorState extends State<KeywordChipsEditor> {
  final _input = TextEditingController();

  List<String> get _words => [
    for (final part in widget.controller.text.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  void _write(List<String> words) {
    widget.controller.text = words.join(', ');
    setState(() {});
  }

  void _commit() {
    final next = _input.text.trim();
    _input.clear();
    if (next.isEmpty) return;
    final words = _words;
    if (words.any((word) => word.toLowerCase() == next.toLowerCase())) return;
    _write([...words, next]);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final words = _words;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Trefwoorden'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        if (words.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final word in words)
                InputChip(
                  label: Text(word),
                  onDeleted: widget.enabled
                      ? () => _write([
                          for (final item in words)
                            if (item != word) item,
                        ])
                      : null,
                ),
            ],
          ),
        Tooltip(
          message: l10n.d('Typ een trefwoord en druk op Enter'),
          child: TextField(
            key: const Key('keyword-chip-input'),
            controller: _input,
            enabled: widget.enabled,
            decoration: InputDecoration(
              isDense: true,
              hintText: l10n.d(
                'Komma-gescheiden, bijv. kwartaal, cijfers, 2026',
              ),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: widget.enabled ? (_) => _commit() : null,
            onChanged: widget.enabled
                ? (value) {
                    if (!value.contains(',')) return;
                    _input.text = value.replaceAll(',', '').trim();
                    _commit();
                  }
                : null,
          ),
        ),
      ],
    );
  }
}
