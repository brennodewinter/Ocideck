import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/question.dart';
import '../../models/slide.dart';
import '../../services/image_service.dart';
import '_editor_field.dart';
import '../../theme/app_theme.dart';

/// Editor for a question slide. Today only multiple choice is wired up; the
/// `kind` dropdown is present so future question kinds slot in here.
class QuestionEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final ImageService imageService;
  final List<String> searchPaths;
  final String? captionBasePath;
  final bool nestedInScrollView;

  const QuestionEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    required this.imageService,
    this.searchPaths = const [],
    this.captionBasePath,
    this.nestedInScrollView = false,
  });

  @override
  State<QuestionEditor> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends State<QuestionEditor> {
  late final TextEditingController _title;
  late final TextEditingController _prompt;
  late final TextEditingController _timeLimit;
  late List<TextEditingController> _answers;
  late List<bool> _correct;
  late int _optionCount;
  late QuestionOnWrong _onWrong;
  late QuestionKind _kind;
  late bool _statementIsTrue;

  @override
  void initState() {
    super.initState();
    final spec = QuestionSpec.parse(widget.slide.customMarkdown);
    _title = TextEditingController(text: widget.slide.title);
    _title.addListener(_emit);
    _prompt = TextEditingController(text: spec.prompt);
    _prompt.addListener(_emit);
    _timeLimit = TextEditingController(
      text: spec.timeLimitSeconds > 0 ? '${spec.timeLimitSeconds}' : '',
    );
    _timeLimit.addListener(_emit);
    _optionCount = spec.optionCount;
    _onWrong = spec.onWrong;
    _kind = spec.kind;
    _statementIsTrue = spec.statementIsTrue;
    final answers = spec.answers.isEmpty
        ? [const QuestionAnswer()]
        : spec.answers;
    _answers = answers.map((a) => _makeCtrl(a.text)).toList();
    _correct = answers.map((a) => a.correct).toList();
  }

  TextEditingController _makeCtrl(String text) {
    final c = TextEditingController(text: text);
    c.addListener(_emit);
    return c;
  }

  QuestionSpec _buildSpec() => QuestionSpec(
    kind: _kind,
    prompt: _prompt.text,
    answers: [
      for (var i = 0; i < _answers.length; i++)
        QuestionAnswer(text: _answers[i].text, correct: _correct[i]),
    ],
    optionCount: _optionCount,
    timeLimitSeconds: int.tryParse(_timeLimit.text.trim()) ?? 0,
    onWrong: _onWrong,
    statementIsTrue: _statementIsTrue,
  );

  void _emit() {
    widget.onUpdate(
      widget.slide.copyWith(
        title: _title.text,
        customMarkdown: _buildSpec().toBlock(),
      ),
    );
  }

  void _addAnswer() {
    setState(() {
      _answers.add(_makeCtrl(''));
      _correct.add(false);
    });
    _emit();
  }

  /// Wissel antwoord [i] met zijn buur ([delta] = -1 of 1) — de lijstvolgorde
  /// is bij een volgorde-vraag het juiste antwoord.
  void _moveAnswer(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= _answers.length) return;
    setState(() {
      final ctrl = _answers[i];
      _answers[i] = _answers[j];
      _answers[j] = ctrl;
      final flag = _correct[i];
      _correct[i] = _correct[j];
      _correct[j] = flag;
    });
    _emit();
  }

  void _removeAnswer(int i) {
    if (_answers.length <= 1) return;
    setState(() {
      _answers[i].removeListener(_emit);
      _answers[i].dispose();
      _answers.removeAt(i);
      _correct.removeAt(i);
    });
    _emit();
  }

  @override
  void dispose() {
    _title.dispose();
    _prompt.dispose();
    _timeLimit.dispose();
    for (final c in _answers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isTrueFalse = _kind == QuestionKind.trueFalse;
    final isMulti = _kind == QuestionKind.multipleCorrect;
    final isOrdering = _kind == QuestionKind.ordering;
    final filledCorrect = [
      for (var i = 0; i < _answers.length; i++)
        if (_correct[i] && _answers[i].text.trim().isNotEmpty) i,
    ];
    final filledWrong = [
      for (var i = 0; i < _answers.length; i++)
        if (!_correct[i] && _answers[i].text.trim().isNotEmpty) i,
    ];

    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        DropdownButtonFormField<QuestionKind>(
          initialValue: _kind,
          decoration: InputDecoration(
            labelText: l10n.d('Soort vraag'),
            isDense: true,
          ),
          items: [
            DropdownMenuItem(
              value: QuestionKind.multipleChoice,
              child: Text(l10n.d('Meerkeuze')),
            ),
            DropdownMenuItem(
              value: QuestionKind.trueFalse,
              child: Text(l10n.d('Juist / Onjuist')),
            ),
            DropdownMenuItem(
              value: QuestionKind.multipleCorrect,
              child: Text(l10n.d('Meerdere juiste antwoorden')),
            ),
            DropdownMenuItem(
              value: QuestionKind.ordering,
              child: Text(l10n.d('Volgorde')),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _kind = value);
            _emit();
          },
        ),
        const SizedBox(height: 16),
        EditorField(
          label: isTrueFalse ? l10n.d('Stelling') : l10n.d('Vraag'),
          controller: _prompt,
          hint: isTrueFalse
              ? l10n.d('Formuleer een stelling die juist of onjuist is')
              : l10n.d('Wat wil je vragen?'),
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        if (isTrueFalse)
          ..._buildTrueFalseSection(l10n)
        else if (isOrdering)
          ..._orderingSection(l10n)
        else
          ..._answersSection(
            l10n,
            isMulti: isMulti,
            filledCorrect: filledCorrect,
            filledWrong: filledWrong,
          ),
        const SizedBox(height: 20),
        const SectionLabel('Weergave'),
        if (!isTrueFalse) ...[
          _buildOptionCountRow(l10n),
          const SizedBox(height: 12),
        ],
        EditorField(
          label: l10n.d('Maximale antwoordtijd in seconden (0 = geen limiet)'),
          controller: _timeLimit,
          hint: '0',
        ),
        const SizedBox(height: 12),
        Text(
          l10n.d('Bij een fout antwoord'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        SegmentedButton<QuestionOnWrong>(
          segments: [
            ButtonSegment(
              value: QuestionOnWrong.retry,
              icon: const Icon(Icons.replay, size: 16),
              label: Text(l10n.d('Opnieuw proberen')),
            ),
            ButtonSegment(
              value: QuestionOnWrong.lockAndContinue,
              icon: const Icon(Icons.lock_open, size: 16),
              label: Text(l10n.d('Doorgaan toestaan')),
            ),
          ],
          selected: {_onWrong},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            setState(() => _onWrong = selection.first);
            _emit();
          },
        ),
        const SizedBox(height: 6),
        Text(
          _onWrong == QuestionOnWrong.retry
              ? l10n.d('Fout = niet doorgaan; de vraag moet opnieuw.')
              : l10n.d('Fout = wel doorgaan, maar niet opnieuw doen.'),
          style: const TextStyle(fontSize: 12, color: AppTheme.slate500),
        ),
        const SizedBox(height: 20),
        ..._imageSection(),
      ],
    );
  }

  List<Widget> _answersSection(
    AppLocalizations l10n, {
    required bool isMulti,
    required List<int> filledCorrect,
    required List<int> filledWrong,
  }) {
    return [
      const SectionLabel('Antwoorden'),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          isMulti
              ? l10n.d(
                  'Markeer alle juiste antwoorden. Bij presenteren wordt willekeurig een set getoond met minstens één juist en één fout.',
                )
              : l10n.d(
                  'Markeer de goede antwoorden. Geen limiet; bij presenteren wordt willekeurig 1 goed en de rest fout getoond.',
                ),
          style: const TextStyle(fontSize: 12, color: AppTheme.slate500),
        ),
      ),
      for (int i = 0; i < _answers.length; i++) _buildAnswerRow(i),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _addAnswer,
          icon: const Icon(Icons.add, size: 16),
          label: Text(l10n.d('Antwoord toevoegen')),
        ),
      ),
      if (filledCorrect.isEmpty || filledWrong.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: Color(0xFFB45309),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.d('Geef minstens één goed én één fout antwoord op.'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFB45309),
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  /// Antwoorden voor een volgorde-vraag: geen goed/fout-vinkjes, maar
  /// omhoog/omlaag-knoppen — de lijstvolgorde hier ís de juiste volgorde.
  List<Widget> _orderingSection(AppLocalizations l10n) {
    final filledCount = _answers.where((c) => c.text.trim().isNotEmpty).length;
    return [
      const SectionLabel('Antwoorden'),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          l10n.d(
            'Zet de antwoorden hier in de juiste volgorde. Bij presenteren worden ze geschud getoond.',
          ),
          style: const TextStyle(fontSize: 12, color: AppTheme.slate500),
        ),
      ),
      for (int i = 0; i < _answers.length; i++) _buildOrderingRow(i),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _addAnswer,
          icon: const Icon(Icons.add, size: 16),
          label: Text(l10n.d('Antwoord toevoegen')),
        ),
      ),
      if (filledCount < 2)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: Color(0xFFB45309),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.d('Geef minstens twee antwoorden op.'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFB45309),
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _buildOrderingRow(int i) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '${i + 1}.',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.slate500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _answers[i],
              decoration: InputDecoration(
                hintText: '${l10n.d('Antwoord')} ${i + 1}',
                isDense: true,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.arrow_upward,
              size: 18,
              color: AppTheme.slate500,
            ),
            onPressed: i > 0 ? () => _moveAnswer(i, -1) : null,
            tooltip: l10n.d('Omhoog'),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 28),
          ),
          IconButton(
            icon: const Icon(
              Icons.arrow_downward,
              size: 18,
              color: AppTheme.slate500,
            ),
            onPressed: i < _answers.length - 1 ? () => _moveAnswer(i, 1) : null,
            tooltip: l10n.d('Omlaag'),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 28),
          ),
          IconButton(
            icon: const Icon(
              Icons.remove_circle_outline,
              size: 18,
              color: AppTheme.slate500,
            ),
            onPressed: _answers.length > 1 ? () => _removeAnswer(i) : null,
            tooltip: l10n.d('Verwijder'),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 28),
          ),
        ],
      ),
    );
  }

  List<Widget> _imageSection() {
    return [
      const SectionLabel('Afbeelding (optioneel)'),
      ImagePickerBar(
        imagePath: widget.slide.imagePath,
        imageCaption: widget.slide.imageCaption,
        searchPaths: widget.searchPaths,
        captionBasePath: widget.captionBasePath,
        onPicked: (path, caption) => widget.onUpdate(
          widget.slide.copyWith(imagePath: path, imageCaption: caption),
        ),
        onBrowse: () async {
          final path = await widget.imageService.pickImage(
            projectPath: widget.captionBasePath,
          );
          if (path != null) {
            widget.onUpdate(widget.slide.copyWith(imagePath: path));
          }
        },
        onPaste: () async {
          final path = await widget.imageService.pasteImage(
            projectPath: widget.captionBasePath,
          );
          if (path != null) {
            widget.onUpdate(widget.slide.copyWith(imagePath: path));
          }
        },
        onClear: widget.slide.imagePath.isNotEmpty
            ? () => widget.onUpdate(
                widget.slide.copyWith(imagePath: '', imageCaption: ''),
              )
            : null,
        onCaptionChanged: (caption) =>
            widget.onUpdate(widget.slide.copyWith(imageCaption: caption)),
      ),
      if (widget.slide.imagePath.isNotEmpty) ...[
        const SizedBox(height: 12),
        const SectionLabel('Breedte afbeelding'),
        ImageZoomControl(
          value: widget.slide.imageSize,
          onChanged: (v) =>
              widget.onUpdate(widget.slide.copyWith(imageSize: v)),
        ),
      ],
    ];
  }

  List<Widget> _buildTrueFalseSection(AppLocalizations l10n) {
    return [
      const SectionLabel('Het juiste antwoord'),
      const SizedBox(height: 4),
      SegmentedButton<bool>(
        segments: [
          ButtonSegment(value: true, label: Text(l10n.d('Juist'))),
          ButtonSegment(value: false, label: Text(l10n.d('Onjuist'))),
        ],
        selected: {_statementIsTrue},
        showSelectedIcon: false,
        onSelectionChanged: (selection) {
          setState(() => _statementIsTrue = selection.first);
          _emit();
        },
      ),
      const SizedBox(height: 6),
      Text(
        l10n.d('De stelling hierboven is juist of onjuist; kies welke.'),
        style: const TextStyle(fontSize: 12, color: AppTheme.slate500),
      ),
    ];
  }

  Widget _buildAnswerRow(int i) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Tooltip(
            message: l10n.d('Goed antwoord'),
            child: Checkbox(
              value: _correct[i],
              onChanged: (value) {
                setState(() => _correct[i] = value ?? false);
                _emit();
              },
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _answers[i],
              decoration: InputDecoration(
                hintText: '${l10n.d('Antwoord')} ${i + 1}',
                isDense: true,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.remove_circle_outline,
              size: 18,
              color: AppTheme.slate500,
            ),
            onPressed: _answers.length > 1 ? () => _removeAnswer(i) : null,
            tooltip: l10n.d('Verwijder'),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCountRow(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.d('Aantal getoonde opties'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        IconButton(
          tooltip: l10n.d('Optie verwijderen'),
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: _optionCount > questionMinOptionCount
              ? () {
                  setState(() => _optionCount--);
                  _emit();
                }
              : null,
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$_optionCount',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: l10n.d('Optie toevoegen'),
          icon: const Icon(Icons.add_circle_outline),
          onPressed: _optionCount < questionMaxOptionCount
              ? () {
                  setState(() => _optionCount++);
                  _emit();
                }
              : null,
        ),
      ],
    );
  }
}
