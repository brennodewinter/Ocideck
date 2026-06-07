import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../l10n/app_localizations.dart';
import '../../models/chart.dart';
import '../../models/slide.dart';
import '_editor_field.dart';

/// Editor for a chart slide: type, title, and the data as a CSV-style table.
/// Data can be typed/pasted, imported from a CSV (inline), or linked to a
/// CSV file kept next to the deck (the living source).
class ChartEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final String? projectPath;

  const ChartEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.projectPath,
  });

  @override
  State<ChartEditor> createState() => _ChartEditorState();
}

class _ChartEditorState extends State<ChartEditor> {
  late final TextEditingController _title;
  late final TextEditingController _csv;
  late ChartType _type;
  String? _source;

  @override
  void initState() {
    super.initState();
    final spec = ChartSpec.parse(widget.slide.customMarkdown);
    _type = spec.type;
    _source = spec.source;
    _title = TextEditingController(text: spec.title);
    _title.addListener(_emit);
    _csv = TextEditingController(text: _specToCsv(spec));
    _csv.addListener(_emit);
  }

  @override
  void dispose() {
    _title.dispose();
    _csv.dispose();
    super.dispose();
  }

  /// Render the spec's inline data back to the CSV-style table text.
  static String _specToCsv(ChartSpec spec) {
    if (!spec.hasInlineData) return '';
    final header = ['', ...spec.series.map((s) => s.name)].join(', ');
    final rows = <String>[header];
    for (var i = 0; i < spec.x.length; i++) {
      rows.add(
        [
          spec.x[i],
          ...spec.series.map(
            (s) => i < s.data.length ? _fmt(s.data[i]) : '',
          ),
        ].join(', '),
      );
    }
    return rows.join('\n');
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  void _emit() {
    final parsed = parseCsv(_csv.text);
    final spec = ChartSpec(
      type: _type,
      title: _title.text,
      source: _source,
      x: parsed.$1,
      series: parsed.$2,
    );
    widget.onUpdate(widget.slide.copyWith(customMarkdown: spec.toBlock()));
  }

  Future<void> _importCsv() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final text = file.bytes != null
        ? utf8.decode(file.bytes!)
        : (file.path != null ? await File(file.path!).readAsString() : null);
    if (text == null) return;

    // Offer to keep the CSV as an external, living source when the deck is
    // saved (so it can be re-edited in a spreadsheet); otherwise inline it.
    var asFile = false;
    if (widget.projectPath != null && mounted) {
      asFile =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(ctx.l10n.d('CSV importeren')),
              content: Text(
                ctx.l10n.d(
                  'Data in de slide opslaan, of als los CSV-bestand naast de presentatie bewaren?',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(ctx.l10n.d('In de slide')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(ctx.l10n.d('Als CSV-bestand')),
                ),
              ],
            ),
          ) ??
          false;
    }

    String? source;
    if (asFile && widget.projectPath != null) {
      final name = p.basename(file.name);
      final dir = Directory(p.join(widget.projectPath!, 'data'));
      await dir.create(recursive: true);
      await File(p.join(dir.path, name)).writeAsString(text, flush: true);
      source = 'data/$name';
    }

    setState(() {
      _source = source;
      _csv.text = text;
    });
    _emit();
  }

  void _unlink() {
    setState(() => _source = null);
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final linked = _source != null;
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
                l10n.d('Type grafiek'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<ChartType>(
                value: _type,
                isDense: true,
                borderRadius: BorderRadius.circular(6),
                style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A)),
                items: [
                  DropdownMenuItem(
                    value: ChartType.bar,
                    child: Text(l10n.d('Staaf')),
                  ),
                  DropdownMenuItem(
                    value: ChartType.line,
                    child: Text(l10n.d('Lijn')),
                  ),
                  DropdownMenuItem(
                    value: ChartType.pie,
                    child: Text(l10n.d('Cirkel')),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _type = v);
                  _emit();
                },
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _importCsv,
                icon: const Icon(Icons.upload_file, size: 16),
                label: Text(l10n.d('CSV importeren')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                l10n.d('Data (CSV: eerste rij = reeksnamen, eerste kolom = labels)'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          if (linked)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const Icon(Icons.link, size: 14, color: Color(0xFF0369A1)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${l10n.d('Gekoppeld aan')} $_source',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF0369A1),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: _unlink,
                    child: Text(l10n.d('Ontkoppelen')),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Expanded(
            child: TextField(
              controller: _csv,
              readOnly: linked,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                hintText: ', 2025, 2026\nQ1, 10, 12\nQ2, 14, 9',
                alignLabelWithHint: true,
                filled: linked,
                fillColor: linked ? const Color(0xFFF1F5F9) : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
