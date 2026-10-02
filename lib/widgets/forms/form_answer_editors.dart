// De invoervelden van een formulier, één per veldtype (FORM_INTAKE.md §4.5, §8).
//
// Elk veld toont een *concept* van het antwoord ([FormAnswerValue]) en meldt elke
// wijziging als een nieuwe waarde; wat er met die waarde gebeurt — in het
// document zetten, controleren, weigeren — weet dit bestand niet. Het concept
// komt van de [FormFieldCard] die het bewaart: tijdens het typen is het concept
// de waarheid, niet het document, want het document kent alleen de opgeschoonde
// vorm (een spatie aan het eind, een leeg punt in een lijst) en zou de invuller
// zijn eigen tekst onder de vingers weghalen.
//
// De tekstvelden houden zelf een controller; die wordt alleen bijgewerkt als de
// waarde die hij krijgt ánders is dan wat er al in staat — dat is dan een
// wijziging van buitenaf (ongedaan maken), nooit de echo van het typen.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import '../../l10n/app_localizations.dart';
import 'form_text_helpers.dart';

/// Het veld voor [field], met [value] als concept.
class FormAnswerEditor extends StatelessWidget {
  const FormAnswerEditor({
    super.key,
    required this.field,
    required this.value,
    required this.onChanged,
    required this.label,
    this.labelBuilder,
    this.onAddImages,
  });

  final FormFieldSpec field;
  final FormAnswerValue value;
  final ValueChanged<FormAnswerValue> onChanged;

  /// De korte naam van het veld, voor de schermlezer.
  final String label;

  /// Tekent het label (Markdown) van het veld; een toestemmingsveld zet het naast
  /// zijn vakje in plaats van erboven.
  final Widget Function(BuildContext context)? labelBuilder;

  /// Voegt foto's toe aan een afbeeldingsveld; `null` zolang er geen manier is om
  /// bestanden te kiezen (het web zonder bestandskiezer, of een test).
  final Future<List<FormImageRef>> Function()? onAddImages;

  @override
  Widget build(BuildContext context) {
    switch (field.type) {
      case 'text':
      case 'number':
      case 'date':
        return _LineAnswer(
          field: field,
          value: value,
          onChanged: onChanged,
          label: label,
        );
      case 'prose':
        return _ProseAnswer(value: value, onChanged: onChanged, label: label);
      case 'choice':
        return _ChoiceAnswer(
          field: field,
          value: value,
          onChanged: onChanged,
          label: label,
        );
      case 'multichoice':
        return _MultichoiceAnswer(
          field: field,
          value: value,
          onChanged: onChanged,
          label: label,
        );
      case 'list':
        return _ListAnswer(
          field: field,
          value: value,
          onChanged: onChanged,
          label: label,
        );
      case 'table':
        return _TableAnswer(
          field: field,
          value: value,
          onChanged: onChanged,
          label: label,
        );
      case 'image':
        return _ImageAnswer(
          field: field,
          value: value,
          onChanged: onChanged,
          label: label,
          onAddImages: onAddImages,
        );
      case 'consent':
        return _ConsentAnswer(
          value: value,
          onChanged: onChanged,
          label: label,
          labelBuilder: labelBuilder,
        );
    }
    return const SizedBox.shrink();
  }
}

/// Houdt een tekstveld en zijn controller gelijk aan de waarde van buitenaf, zonder
/// de cursor te verplaatsen tijdens het typen.
void _syncController(TextEditingController controller, String text) {
  if (controller.text == text) return;
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
}

// ── één regel: tekst, getal, datum ──────────────────────────────────────────

class _LineAnswer extends StatefulWidget {
  const _LineAnswer({
    required this.field,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final FormFieldSpec field;
  final FormAnswerValue value;
  final ValueChanged<FormAnswerValue> onChanged;
  final String label;

  @override
  State<_LineAnswer> createState() => _LineAnswerState();
}

class _LineAnswerState extends State<_LineAnswer> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value.text ?? '',
  );

  @override
  void didUpdateWidget(_LineAnswer old) {
    super.didUpdateWidget(old);
    _syncController(_controller, widget.value.text ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _parse(_controller.text) ?? now,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (picked == null) return;
    widget.onChanged(FormAnswerValue(text: formatFormDate(picked)));
  }

  /// De datum in het veld, of `null` als er (nog) geen geldige staat.
  static DateTime? _parse(String text) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text.trim());
    if (m == null) return null;
    final date = DateTime.tryParse(m.group(0)!);
    return date;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final type = widget.field.type;
    return Semantics(
      label: widget.label,
      child: TextField(
        controller: _controller,
        maxLines: 1,
        keyboardType: type == 'number'
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        inputFormatters: type == 'number'
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-+ ]'))]
            : null,
        decoration: InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          hintText: type == 'date' ? l10n.d('YYYY-MM-DD') : null,
          suffixIcon: type == 'date'
              ? IconButton(
                  tooltip: l10n.d('Kies een datum'),
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  onPressed: _pickDate,
                )
              : null,
        ),
        onChanged: (text) => widget.onChanged(FormAnswerValue(text: text)),
      ),
    );
  }
}

// ── lopende tekst ───────────────────────────────────────────────────────────

class _ProseAnswer extends StatefulWidget {
  const _ProseAnswer({
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final FormAnswerValue value;
  final ValueChanged<FormAnswerValue> onChanged;
  final String label;

  @override
  State<_ProseAnswer> createState() => _ProseAnswerState();
}

class _ProseAnswerState extends State<_ProseAnswer> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value.text ?? '',
  );

  @override
  void didUpdateWidget(_ProseAnswer old) {
    super.didUpdateWidget(old);
    _syncController(_controller, widget.value.text ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      child: TextField(
        controller: _controller,
        minLines: 6,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
        onChanged: (text) => widget.onChanged(FormAnswerValue(text: text)),
      ),
    );
  }
}

// ── één keuze ───────────────────────────────────────────────────────────────

/// De sleutel van de radioknop "anders" in de keuzegroep. Geen echte optie kan
/// zo heten: een optie komt uit een `|`-lijst in een marker.
const String _otherKey = '\u0000other';

class _ChoiceAnswer extends StatefulWidget {
  const _ChoiceAnswer({
    required this.field,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final FormFieldSpec field;
  final FormAnswerValue value;
  final ValueChanged<FormAnswerValue> onChanged;
  final String label;

  @override
  State<_ChoiceAnswer> createState() => _ChoiceAnswerState();
}

class _ChoiceAnswerState extends State<_ChoiceAnswer> {
  late final TextEditingController _other = TextEditingController(
    text: _ownText,
  );

  /// Of "anders" gekozen is. Apart bewaard: wie "anders" kiest en nog niets heeft
  /// getypt heeft een leeg antwoord, en dan zou de keuze meteen weer wegvallen.
  late bool _otherChosen = _ownText.isNotEmpty;

  List<String> get _options => widget.field.list('options') ?? const [];

  /// De eigen tekst: een antwoord dat geen van de opties is.
  String get _ownText {
    final text = widget.value.text ?? '';
    return text.isNotEmpty && !_options.contains(text) ? text : '';
  }

  @override
  void didUpdateWidget(_ChoiceAnswer old) {
    super.didUpdateWidget(old);
    final text = widget.value.text ?? '';
    if (_options.contains(text)) _otherChosen = false;
    if (_otherChosen || _ownText.isNotEmpty) _syncController(_other, _ownText);
    if (_ownText.isNotEmpty) _otherChosen = true;
  }

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  void _choose(String? key) {
    if (key == null) return;
    if (key == _otherKey) {
      setState(() => _otherChosen = true);
      widget.onChanged(FormAnswerValue(text: _other.text));
    } else {
      setState(() => _otherChosen = false);
      widget.onChanged(FormAnswerValue(text: key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = widget.value.text ?? '';
    final group = _otherChosen
        ? _otherKey
        : (_options.contains(text) ? text : null);
    return Semantics(
      label: widget.label,
      child: RadioGroup<String>(
        groupValue: group,
        onChanged: _choose,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final option in _options)
              RadioListTile<String>(
                value: option,
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(option),
              ),
            if (widget.field.flag('other')) ...[
              RadioListTile<String>(
                value: _otherKey,
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.d('Anders, namelijk:')),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 40, bottom: 4),
                child: TextField(
                  controller: _other,
                  maxLines: 1,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (text) {
                    setState(() => _otherChosen = true);
                    widget.onChanged(FormAnswerValue(text: text));
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── meerdere keuzes ─────────────────────────────────────────────────────────

class _MultichoiceAnswer extends StatefulWidget {
  const _MultichoiceAnswer({
    required this.field,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final FormFieldSpec field;
  final FormAnswerValue value;
  final ValueChanged<FormAnswerValue> onChanged;
  final String label;

  @override
  State<_MultichoiceAnswer> createState() => _MultichoiceAnswerState();
}

class _MultichoiceAnswerState extends State<_MultichoiceAnswer> {
  late final TextEditingController _other = TextEditingController(
    text: _ownText,
  );

  List<String> get _options => widget.field.list('options') ?? const [];

  String get _ownText => widget.value.items.firstWhere(
    (item) => !_options.contains(item),
    orElse: () => '',
  );

  @override
  void didUpdateWidget(_MultichoiceAnswer old) {
    super.didUpdateWidget(old);
    _syncController(_other, _ownText);
  }

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  void _emit(Set<String> chosen, String own) {
    widget.onChanged(
      FormAnswerValue(
        items: [
          for (final option in _options)
            if (chosen.contains(option)) option,
          if (own.trim().isNotEmpty) own,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final chosen = {
      for (final item in widget.value.items)
        if (_options.contains(item)) item,
    };
    return Semantics(
      label: widget.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final option in _options)
            CheckboxListTile(
              value: chosen.contains(option),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(option),
              onChanged: (on) => _emit(
                on == true
                    ? {...chosen, option}
                    : ({...chosen}..remove(option)),
                _other.text,
              ),
            ),
          if (widget.field.flag('other')) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(l10n.d('Anders, namelijk:')),
            ),
            TextField(
              controller: _other,
              maxLines: 1,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (text) => _emit(chosen, text),
            ),
          ],
        ],
      ),
    );
  }
}

// ── een lijst ───────────────────────────────────────────────────────────────

class _ListAnswer extends StatefulWidget {
  const _ListAnswer({
    required this.field,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final FormFieldSpec field;
  final FormAnswerValue value;
  final ValueChanged<FormAnswerValue> onChanged;
  final String label;

  @override
  State<_ListAnswer> createState() => _ListAnswerState();
}

class _ListAnswerState extends State<_ListAnswer> {
  final List<TextEditingController> _controllers = [];

  @override
  void initState() {
    super.initState();
    _align();
  }

  @override
  void didUpdateWidget(_ListAnswer old) {
    super.didUpdateWidget(old);
    _align();
  }

  /// Brengt de controllers op één lijn met de punten van het concept: net zoveel,
  /// elk met zijn eigen tekst.
  void _align() {
    final items = widget.value.items;
    while (_controllers.length > items.length) {
      _controllers.removeLast().dispose();
    }
    while (_controllers.length < items.length) {
      _controllers.add(TextEditingController());
    }
    for (var i = 0; i < items.length; i++) {
      _syncController(_controllers[i], items[i]);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _emit(List<String> items) =>
      widget.onChanged(FormAnswerValue(items: items));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = widget.value.items;
    final ordered = widget.field.flag('ordered');
    return Semantics(
      label: widget.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(ordered ? '${i + 1}.' : '•'),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controllers[i],
                      maxLines: null,
                      decoration: InputDecoration(
                        isDense: true,
                        border: const OutlineInputBorder(),
                        hintText: l10n
                            .d('Punt {n}')
                            .replaceAll('{n}', '${i + 1}'),
                      ),
                      onChanged: (text) => _emit([...items]..[i] = text),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n
                        .d('Punt {n} verwijderen')
                        .replaceAll('{n}', '${i + 1}'),
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => _emit([...items]..removeAt(i)),
                  ),
                ],
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.d('Punt toevoegen')),
              onPressed: () => _emit([...items, '']),
            ),
          ),
        ],
      ),
    );
  }
}

// ── een tabel ───────────────────────────────────────────────────────────────

class _TableAnswer extends StatefulWidget {
  const _TableAnswer({
    required this.field,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final FormFieldSpec field;
  final FormAnswerValue value;
  final ValueChanged<FormAnswerValue> onChanged;
  final String label;

  @override
  State<_TableAnswer> createState() => _TableAnswerState();
}

class _TableAnswerState extends State<_TableAnswer> {
  final List<List<TextEditingController>> _controllers = [];

  List<String> get _columns => widget.field.list('columns') ?? const [];

  @override
  void initState() {
    super.initState();
    _align();
  }

  @override
  void didUpdateWidget(_TableAnswer old) {
    super.didUpdateWidget(old);
    _align();
  }

  void _align() {
    final rows = widget.value.rows;
    while (_controllers.length > rows.length) {
      for (final c in _controllers.removeLast()) {
        c.dispose();
      }
    }
    while (_controllers.length < rows.length) {
      _controllers.add([
        for (var c = 0; c < _columns.length; c++) TextEditingController(),
      ]);
    }
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < _columns.length; c++) {
        _syncController(
          _controllers[r][c],
          c < rows[r].length ? rows[r][c] : '',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final row in _controllers) {
      for (final c in row) {
        c.dispose();
      }
    }
    super.dispose();
  }

  List<List<String>> get _rows => [
    for (final row in widget.value.rows)
      [for (var c = 0; c < _columns.length; c++) c < row.length ? row[c] : ''],
  ];

  void _emit(List<List<String>> rows) =>
      widget.onChanged(FormAnswerValue(rows: rows));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    final rows = _rows;
    return Semantics(
      label: widget.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final column in _columns)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6, bottom: 4),
                    child: Text(column, style: textTheme.labelLarge),
                  ),
                ),
              const SizedBox(width: 40),
            ],
          ),
          for (var r = 0; r < rows.length; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var c = 0; c < _columns.length; c++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Semantics(
                          label: _columns[c],
                          child: TextField(
                            controller: _controllers[r][c],
                            maxLines: 1,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (text) {
                              final next = _rows;
                              next[r][c] = text;
                              _emit(next);
                            },
                          ),
                        ),
                      ),
                    ),
                  SizedBox(
                    width: 34,
                    child: IconButton(
                      tooltip: l10n
                          .d('Rij {n} verwijderen')
                          .replaceAll('{n}', '${r + 1}'),
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => _emit([...rows]..removeAt(r)),
                    ),
                  ),
                ],
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.d('Rij toevoegen')),
              onPressed: () => _emit([
                ...rows,
                [for (final _ in _columns) ''],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── foto's ──────────────────────────────────────────────────────────────────

class _ImageAnswer extends StatefulWidget {
  const _ImageAnswer({
    required this.field,
    required this.value,
    required this.onChanged,
    required this.label,
    required this.onAddImages,
  });

  final FormFieldSpec field;
  final FormAnswerValue value;
  final ValueChanged<FormAnswerValue> onChanged;
  final String label;
  final Future<List<FormImageRef>> Function()? onAddImages;

  @override
  State<_ImageAnswer> createState() => _ImageAnswerState();
}

class _ImageAnswerState extends State<_ImageAnswer> {
  final List<TextEditingController> _alts = [];
  final List<TextEditingController> _credits = [];

  @override
  void initState() {
    super.initState();
    _align();
  }

  @override
  void didUpdateWidget(_ImageAnswer old) {
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
      _syncController(_alts[i], images[i].alt);
      _syncController(_credits[i], images[i].credit ?? '');
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
    final added = await widget.onAddImages!();
    if (added.isEmpty) return;
    _emit([...widget.value.images, ...added]);
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
                      const Icon(Icons.image_outlined, size: 18),
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
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: Text(l10n.d('Foto toevoegen')),
                onPressed: _add,
              ),
            ),
        ],
      ),
    );
  }
}

// ── toestemming ─────────────────────────────────────────────────────────────

class _ConsentAnswer extends StatelessWidget {
  const _ConsentAnswer({
    required this.value,
    required this.onChanged,
    required this.label,
    required this.labelBuilder,
  });

  final FormAnswerValue value;
  final ValueChanged<FormAnswerValue> onChanged;
  final String label;
  final Widget Function(BuildContext context)? labelBuilder;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: CheckboxListTile(
        value: value.consent == true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: labelBuilder?.call(context) ?? Text(label),
        onChanged: (on) => onChanged(FormAnswerValue(consent: on == true)),
      ),
    );
  }
}
