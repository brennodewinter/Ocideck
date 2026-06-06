import 'package:flutter/material.dart';
import '../../models/slide.dart';
import '../../l10n/app_localizations.dart';
import '_editor_field.dart';

/// Editor voor een broncode-slide: een optionele titel, een keuzelijst voor de
/// programmeertaal (voor syntaxkleuring) en een monospace tekstveld voor de code.
class CodeEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;

  const CodeEditor({super.key, required this.slide, required this.onUpdate});

  /// Veelgebruikte talen. De waarde is de highlight.js-id; een lege waarde
  /// betekent platte tekst (geen kleuring).
  static const _languages = <(String, String)>[
    ('', 'Platte tekst'),
    ('dart', 'Dart'),
    ('javascript', 'JavaScript'),
    ('typescript', 'TypeScript'),
    ('python', 'Python'),
    ('java', 'Java'),
    ('kotlin', 'Kotlin'),
    ('swift', 'Swift'),
    ('csharp', 'C#'),
    ('cpp', 'C++'),
    ('c', 'C'),
    ('go', 'Go'),
    ('rust', 'Rust'),
    ('ruby', 'Ruby'),
    ('php', 'PHP'),
    ('bash', 'Shell / Bash'),
    ('sql', 'SQL'),
    ('json', 'JSON'),
    ('yaml', 'YAML'),
    ('xml', 'XML / HTML'),
    ('css', 'CSS'),
    ('markdown', 'Markdown'),
  ];

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  late final TextEditingController _title;
  late final TextEditingController _code;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.slide.title);
    _title.addListener(
      () => widget.onUpdate(widget.slide.copyWith(title: _title.text)),
    );
    _code = TextEditingController(text: widget.slide.customMarkdown);
    _code.addListener(
      () => widget.onUpdate(widget.slide.copyWith(customMarkdown: _code.text)),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Houd de huidige taal selecteerbaar, ook als die niet in de lijst staat.
    final current = widget.slide.codeLanguage.trim();
    final items = [
      ...CodeEditor._languages,
      if (current.isNotEmpty &&
          !CodeEditor._languages.any((e) => e.$1 == current))
        (current, current),
    ];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EditorField(label: 'Titel (optioneel)', controller: _title),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                l10n.d('Programmeertaal'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: items.any((e) => e.$1 == current) ? current : '',
                isDense: true,
                borderRadius: BorderRadius.circular(6),
                style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A)),
                items: [
                  for (final (id, label) in items)
                    DropdownMenuItem(value: id, child: Text(label)),
                ],
                onChanged: (id) {
                  if (id == null) return;
                  widget.onUpdate(widget.slide.copyWith(codeLanguage: id));
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            l10n.d('Broncode'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: TextField(
              controller: _code,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                hintText: l10n.d('Plak of typ hier je broncode...'),
                alignLabelWithHint: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
