import 'package:material_ui/material_ui.dart';
import '../../l10n/app_localizations.dart';
import '../../services/transcription/speaker_corrections.dart';

Future<String?> showSpeakerCorrectionsDialog(
  BuildContext context,
  String source,
) => showDialog<String>(
  context: context,
  builder: (_) => _SpeakerDialog(source: source),
);

class _SpeakerDialog extends StatefulWidget {
  const _SpeakerDialog({required this.source});
  final String source;
  @override
  State<_SpeakerDialog> createState() => _SpeakerDialogState();
}

class _SpeakerDialogState extends State<_SpeakerDialog> {
  late final model = SpeakerCorrections.read(widget.source)!;
  final selected = <int>{};
  String? target;
  String? mergeFrom;
  bool changed = false;
  final _controllers = <TextEditingController>[];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.d('Sprekers corrigeren')),
    content: SizedBox(
      width: 700,
      height: 460,
      child: Column(
        children: [
          Text(context.l10n.d('Selecteer fragmenten.')),
          Expanded(
            child: ListView.builder(
              itemCount: model.lines.length,
              itemBuilder: (_, i) => Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      value: selected.contains(i),
                      onChanged: (v) => setState(() {
                        v == true ? selected.add(i) : selected.remove(i);
                      }),
                      title: Text(model.lines[i]),
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.d('Fragment splitsen'),
                    icon: const Icon(Icons.content_cut),
                    onPressed: () => _split(i),
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  hint: Text(context.l10n.d('Doelspreker')),
                  value: target,
                  items: model.names.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => target = v),
                ),
              ),
              TextButton(
                onPressed: selected.isEmpty || target == null
                    ? null
                    : () => setState(() {
                        model.assign(selected, target!);
                        changed = true;
                      }),
                child: Text(context.l10n.d('Toewijzen')),
              ),
              TextButton(
                onPressed: selected.isEmpty ? null : _newSpeaker,
                child: Text(context.l10n.d('Nieuwe spreker')),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  hint: Text(context.l10n.d('Samenvoegen vanuit')),
                  value: mergeFrom,
                  items: model.names.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => mergeFrom = v),
                ),
              ),
              TextButton(
                onPressed:
                    target == null || mergeFrom == null || target == mergeFrom
                    ? null
                    : _merge,
                child: Text(
                  '${context.l10n.d('Samenvoegen')} (${mergeFrom == null ? 0 : model.mergeCount(mergeFrom!)})',
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.d('Annuleren')),
      ),
      FilledButton(
        onPressed: changed
            ? () => Navigator.pop(context, model.apply(widget.source))
            : null,
        child: Text(context.l10n.d('Toepassen')),
      ),
    ],
  );

  Future<void> _newSpeaker() async {
    final controller = TextEditingController();
    _controllers.add(controller);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.d('Nieuwe spreker')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: context.l10n.d('Naam')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.d('Annuleren')),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty && !RegExp(r'[\r\n*<>]').hasMatch(name)) {
                Navigator.pop(ctx, name);
              }
            },
            child: Text(context.l10n.d('Toewijzen')),
          ),
        ],
      ),
    );
    if (!mounted || name == null) return;
    setState(() {
      target = model.addSpeaker(name);
      model.assign(selected, target!);
      changed = true;
    });
  }

  Future<void> _merge() async {
    final from = mergeFrom!;
    final into = target!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.d('Samenvoegen')),
        content: Text(
          '${model.names[from]} → ${model.names[into]} (${model.mergeCount(from)})',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.d('Annuleren')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.d('Samenvoegen')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      model.merge(from, into);
      mergeFrom = null;
      changed = true;
    });
  }

  Future<void> _split(int i) async {
    final text = model.spokenText(i);
    final controller = TextEditingController(text: text);
    _controllers.add(controller);
    final offset = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.d('Fragment splitsen')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.d(
                'Plaats de cursor bij de sprekerwisseling. Het tweede deel krijgt geen tijdstip.',
              ),
            ),
            TextField(
              controller: controller,
              readOnly: true,
              showCursor: true,
              maxLines: 6,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.d('Annuleren')),
          ),
          TextButton(
            onPressed: () {
              final offset = controller.selection.baseOffset;
              if (offset > 0 &&
                  offset < text.length &&
                  text.substring(0, offset).trim().isNotEmpty &&
                  text.substring(offset).trim().isNotEmpty) {
                Navigator.pop(ctx, offset);
              }
            },
            child: Text(context.l10n.d('Fragment splitsen')),
          ),
        ],
      ),
    );
    if (!mounted || offset == null) return;
    setState(() {
      model.split(i, offset);
      selected.clear();
      selected.add(i + 1);
      changed = true;
    });
  }
}
