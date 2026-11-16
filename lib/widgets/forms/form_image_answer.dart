// De foto's van een afbeeldingsveld: elke foto met een voorbeeld, een
// beschrijving en een maker waar het veld daarom vraagt, en de knop om er een
// toe te voegen. Eigen bestand omdat de invoervelden samen boven de regelgrens
// van het project kwamen.

import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../l10n/app_localizations.dart';
import '../signature_draw_dialog.dart';
import 'form_image_support.dart';
import 'form_text_helpers.dart';

// ── foto's ──────────────────────────────────────────────────────────────────

class FormImageAnswer extends StatefulWidget {
  const FormImageAnswer({
    super.key,
    required this.field,
    required this.value,
    required this.onChanged,
    required this.label,
    required this.onAddImages,
    required this.scrubbed,
    required this.preview,
  });

  final FormFieldSpec field;
  final FormAnswerValue value;
  final ValueChanged<FormAnswerValue> onChanged;
  final String label;
  final FormImageAdders? onAddImages;
  final Set<String> scrubbed;
  final ImageProvider? Function(String path)? preview;

  @override
  State<FormImageAnswer> createState() => _FormImageAnswerState();
}

class _FormImageAnswerState extends State<FormImageAnswer> {
  final List<TextEditingController> _alts = [];
  final List<TextEditingController> _credits = [];

  @override
  void initState() {
    super.initState();
    _align();
  }

  @override
  void didUpdateWidget(FormImageAnswer old) {
    super.didUpdateWidget(old);
    _align();
  }

  void _align() {
    final images = widget.value.images;
    while (_alts.length > images.length) {
      _alts.removeLast().dispose();
      _credits.removeLast().dispose();
    }
    while (_alts.length < images.length) {
      _alts.add(TextEditingController());
      _credits.add(TextEditingController());
    }
    for (var i = 0; i < images.length; i++) {
      syncController(_alts[i], images[i].alt);
      syncController(_credits[i], images[i].credit ?? '');
    }
  }

  @override
  void dispose() {
    for (final c in [..._alts, ..._credits]) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit(List<FormImageRef> images) =>
      widget.onChanged(FormAnswerValue(images: images));

  Future<void> _add() async {
    final added = await widget.onAddImages!.pick();
    if (added.isEmpty) return;
    _emit([...widget.value.images, ...added]);
  }

  /// De bytes van één bron (klembord, tekening, stijllogo) door dezelfde
  /// verwerking als een gekozen bestand.
  Future<void> _addReader(Future<Uint8List> Function() reader) async {
    final read = widget.onAddImages?.read;
    if (read == null) return;
    final added = await read([reader]);
    if (added.isEmpty || !mounted) return;
    _emit([...widget.value.images, ...added]);
  }

  Future<void> _paste() => _addReader(() async {
    final bytes = await Pasteboard.image;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('empty clipboard');
    }
    return bytes;
  });

  /// Een vrije streek op de tekentablet: komt terug als `data:`-URI en gaat
  /// als png-bytes door de gewone inname.
  Future<void> _draw() async {
    final uri = await SignatureDrawDialog.show(context);
    if (uri == null || !mounted) return;
    final comma = uri.indexOf(',');
    if (comma < 0) return;
    final bytes = base64Decode(uri.substring(comma + 1));
    await _addReader(() async => bytes);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final images = widget.value.images;
    final wantsAlt = widget.field.flag('alt');
    final wantsCredit = widget.field.flag('credit');
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: widget.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < images.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _thumbnail(images[i].path),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          images[i].path,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: l10n
                            .d('Foto {n} verwijderen')
                            .replaceAll('{n}', '${i + 1}'),
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => _emit([...images]..removeAt(i)),
                      ),
                    ],
                  ),
                  if (widget.scrubbed.contains(images[i].path))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_off_outlined,
                            size: 14,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              l10n.d(
                                'Locatiegegevens zijn uit deze foto verwijderd.',
                              ),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (wantsAlt)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: TextField(
                        controller: _alts[i],
                        maxLines: 1,
                        decoration: InputDecoration(
                          isDense: true,
                          border: const OutlineInputBorder(),
                          labelText: l10n.d('Wat is er te zien op de foto?'),
                        ),
                        onChanged: (text) => _emit([
                          for (var n = 0; n < images.length; n++)
                            n == i
                                ? FormImageRef(
                                    images[n].path,
                                    text,
                                    images[n].credit,
                                  )
                                : images[n],
                        ]),
                      ),
                    ),
                  if (wantsCredit)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: TextField(
                        controller: _credits[i],
                        maxLines: 1,
                        decoration: InputDecoration(
                          isDense: true,
                          border: const OutlineInputBorder(),
                          labelText: l10n.d('Van wie is de foto?'),
                        ),
                        onChanged: (text) => _emit([
                          for (var n = 0; n < images.length; n++)
                            n == i
                                ? FormImageRef(
                                    images[n].path,
                                    images[n].alt,
                                    text,
                                  )
                                : images[n],
                        ]),
                      ),
                    ),
                ],
              ),
            ),
          if (widget.onAddImages != null)
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  icon: const Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 18,
                  ),
                  label: Text(l10n.d('Foto toevoegen')),
                  onPressed: _add,
                ),
                if (widget.onAddImages!.read != null) ...[
                  TextButton.icon(
                    icon: const Icon(Icons.content_paste, size: 18),
                    label: Text(l10n.d('Plakken')),
                    onPressed: _paste,
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.draw_outlined, size: 18),
                    label: Text(l10n.d('Tekenen')),
                    onPressed: _draw,
                  ),
                  if (widget.onAddImages!.presets.isNotEmpty)
                    PopupMenuButton<FormImagePreset>(
                      itemBuilder: (context) => [
                        for (final preset in widget.onAddImages!.presets)
                          PopupMenuItem(
                            value: preset,
                            child: Text(preset.label),
                          ),
                      ],
                      onSelected: (preset) => _addReader(preset.read),
                      child: TextButton.icon(
                        icon: const Icon(Icons.palette_outlined, size: 18),
                        label: Text(l10n.d('Uit een stijl')),
                        onPressed: null,
                      ),
                    ),
                ],
              ],
            )
          else
            Text(
              l10n.d('Sla het document eerst op om foto’s toe te voegen.'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  /// Een klein voorbeeld van de foto, of een pictogram als er geen is te tekenen.
  Widget _thumbnail(String path) {
    final provider = widget.preview?.call(path);
    if (provider == null) return const Icon(Icons.image_outlined, size: 18);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image(
        image: ResizeImage(provider, width: 144),
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
      ),
    );
  }
}
