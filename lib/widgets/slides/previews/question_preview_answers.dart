part of '../slide_preview.dart';

/// De twee vraagsoorten die niet uit een rijtje tekstopties bestaan: het
/// beeldpaar (twee afbeeldingen, wijs de juiste aan) en het getypte antwoord.
/// Ze delen de kaart en de kleuren van [_QuestionPreview], maar leggen hun
/// inhoud anders neer — vandaar hun eigen opbouw hier.
extension _QuestionPreviewAnswers on _QuestionPreview {
  /// Of deze vraag met afbeeldingen beantwoord wordt. Tijdens het presenteren
  /// telt wat er getrokken is; in de auteursweergave de gekozen soort.
  bool isImageChoice(QuestionSpec spec) => view != null
      ? view!.hasImages
      : spec.kind == QuestionKind.imagePair && spec.filledAnswers.isNotEmpty;

  /// Of deze vraag met een getypt antwoord beantwoord wordt.
  bool isOpenText(QuestionSpec spec) =>
      view != null ? view!.openText : spec.kind == QuestionKind.openText;

  // ── Beeldpaar ──────────────────────────────────────────────────────────────

  /// Twee beelden naast elkaar, elk even breed. Bewust geen rijtje onder
  /// elkaar: de vraag is "welke van deze twee", en dat lees je alleen af als ze
  /// naast elkaar staan.
  Widget imageChoiceContent(BuildContext context, QuestionSpec spec) {
    final textColor = AppTheme.parseHexColor(profile.textColor);
    final accent = AppTheme.parseHexColor(profile.accentColor);
    final prompt = spec.prompt.isEmpty ? '—' : spec.prompt;
    final tiles = _imageTiles(context, spec);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (view != null && view!.hasTimer) SizedBox(height: w * 0.02),
        _md(
          context,
          prompt,
          TextStyle(
            fontFamily: font,
            fontSize: w * 0.042,
            fontWeight: FontWeight.w600,
            color: textColor,
            height: 1.2,
          ),
          linkColor: accent,
        ),
        SizedBox(height: w * 0.025),
        Expanded(
          child: tiles.isEmpty
              ? _emptyImagePairNotice(context)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < tiles.length; i++) ...[
                      if (i > 0) SizedBox(width: w * 0.025),
                      Expanded(child: tiles[i]),
                    ],
                  ],
                ),
        ),
        SizedBox(height: w * 0.018),
        if (view != null && view!.revealed)
          _resultChip(context, 1)
        else if (view == null)
          _authorHint(context, spec, 1)
        else
          _pickInstruction(context),
      ],
    );
  }

  List<Widget> _imageTiles(BuildContext context, QuestionSpec spec) {
    if (view != null) {
      return [
        for (var i = 0; i < view!.options.length; i++)
          _imageTile(
            context,
            index: i,
            path: view!.imageAt(i),
            caption: view!.options[i],
            visual: _presentVisual(i),
          ),
      ];
    }
    final answers = spec.filledAnswers;
    return [
      for (var i = 0; i < answers.length; i++)
        _imageTile(
          context,
          index: i,
          path: answers[i].image,
          caption: answers[i].text,
          visual: answers[i].correct
              ? _OptionVisual.authorCorrect
              : _OptionVisual.neutral,
        ),
    ];
  }

  Widget _emptyImagePairNotice(BuildContext context) => Center(
    child: Text(
      context.l10n.d('Kies twee afbeeldingen en markeer de juiste.'),
      style: TextStyle(
        fontFamily: font,
        fontSize: w * 0.026,
        color: AppTheme.parseHexColor(profile.textColor).withValues(alpha: 0.6),
      ),
      textAlign: TextAlign.center,
    ),
  );

  Widget _imageTile(
    BuildContext context, {
    required int index,
    required String path,
    required String caption,
    required _OptionVisual visual,
  }) {
    final colors = _visualColors(visual);
    final tile = Opacity(
      opacity: colors.opacity,
      child: Container(
        decoration: BoxDecoration(
          color: colors.fill,
          border: Border.all(color: colors.border, width: w * 0.004),
          borderRadius: BorderRadius.circular(w * 0.014),
        ),
        padding: EdgeInsets.all(w * 0.008),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(w * 0.008),
                    child: path.isEmpty
                        ? const SizedBox.shrink()
                        : _resolvedImage(
                            context,
                            path,
                            projectPath,
                            semanticLabel: caption.trim().isEmpty
                                ? '${context.l10n.d('Antwoord')} ${index + 1}'
                                : caption,
                          ),
                  ),
                  Positioned(
                    top: w * 0.01,
                    left: w * 0.01,
                    child: _tileBadge(index, colors),
                  ),
                ],
              ),
            ),
            if (caption.trim().isNotEmpty) ...[
              SizedBox(height: w * 0.01),
              Text(
                caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: font,
                  fontSize: w * 0.024,
                  color: AppTheme.parseHexColor(profile.textColor),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (!_interactive) return tile;
    return InkWell(
      borderRadius: BorderRadius.circular(w * 0.014),
      onTap: () => onAnswerSelected!(index),
      child: tile,
    );
  }

  /// De ronde markering linksboven op een beeld: normaal de letter (A, B), na
  /// het antwoorden het ✓ of ✗.
  Widget _tileBadge(int index, _VisualColors colors) => Container(
    width: w * 0.05,
    height: w * 0.05,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.black.withValues(alpha: 0.55),
    ),
    child: colors.icon == null
        ? Text(
            String.fromCharCode(65 + index),
            style: TextStyle(
              fontFamily: font,
              fontSize: w * 0.026,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          )
        : Icon(colors.icon, color: colors.border, size: w * 0.032),
  );

  Widget _pickInstruction(BuildContext context) => Text(
    context.l10n.d('Tik de juiste afbeelding aan'),
    style: TextStyle(
      fontFamily: font,
      fontSize: w * 0.024,
      color: AppTheme.parseHexColor(profile.textColor).withValues(alpha: 0.7),
    ),
  );

  // ── Getypt antwoord ────────────────────────────────────────────────────────

  /// De vraag met een invoerveld eronder. Vóór het antwoorden staat er niets
  /// van de oplossing op het scherm — ook niet op het beamervenster, want de
  /// [QuestionView] draagt het juiste antwoord pas mee ná het onthullen.
  Widget openTextContent(BuildContext context, QuestionSpec spec) {
    final l10n = context.l10n;
    final textColor = AppTheme.parseHexColor(profile.textColor);
    final accent = AppTheme.parseHexColor(profile.accentColor);
    final prompt = spec.prompt.isEmpty ? '—' : spec.prompt;
    final v = view;

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (v != null && v.hasTimer) SizedBox(height: w * 0.02),
        _md(
          context,
          prompt,
          TextStyle(
            fontFamily: font,
            fontSize: w * 0.046,
            fontWeight: FontWeight.w600,
            color: textColor,
            height: 1.2,
          ),
          linkColor: accent,
        ),
        SizedBox(height: w * 0.03),
        if (v == null)
          ..._openTextAuthorView(context, spec)
        else if (v.revealed)
          // Ná het antwoorden vervangt de correctie het invoerveld: het getypte
          // antwoord staat daar nog een keer, maar dan mét de plekken waar het
          // afweek aangewezen.
          ..._openTextResult(context, v, spec)
        else ...[
          _OpenAnswerField(
            value: v.typedAnswer,
            hint: l10n.d('Typ je antwoord'),
            enabled: !v.locked,
            onChanged: onAnswerTextChanged,
            onSubmit: onAnswerSubmit,
            fontFamily: font,
            fontSize: w * 0.034,
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.025,
              vertical: w * 0.02,
            ),
            radius: w * 0.012,
            textColor: textColor,
            accent: accent,
          ),
          SizedBox(height: w * 0.022),
          if (_interactive) _submitRow(context, 1),
        ],
      ],
    );

    // Ná het antwoorden komt er inhoud bij (het juiste antwoord, het
    // overeenkomstpercentage). Zonder deze krimp liep de dia dan over de rand —
    // precies op het moment dat de kijker naar de uitkomst kijkt.
    return LayoutBuilder(
      builder: (context, constraints) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: SizedBox(width: constraints.maxWidth, child: column),
      ),
    );
  }

  List<Widget> _openTextAuthorView(BuildContext context, QuestionSpec spec) {
    final l10n = context.l10n;
    final accepted = spec.correctAnswers;
    return [
      Text(
        accepted.isEmpty
            ? l10n.d('Nog geen goed antwoord opgegeven.')
            : l10n.d('Goed gerekend antwoord:'),
        style: TextStyle(
          fontFamily: font,
          fontSize: w * 0.024,
          color: AppTheme.parseHexColor(
            profile.textColor,
          ).withValues(alpha: 0.6),
        ),
      ),
      SizedBox(height: w * 0.012),
      for (var i = 0; i < accepted.length; i++) ...[
        if (i > 0) SizedBox(height: w * 0.012),
        _optionTile(
          context,
          accepted[i].text,
          i,
          _OptionVisual.authorCorrect,
          1,
        ),
      ],
      SizedBox(height: w * 0.02),
      _authorHint(context, spec, 1),
    ];
  }

  /// Na het antwoorden: de correctie. Niet alleen "fout" met een percentage,
  /// maar de twee teksten onder elkaar met de verschillen aangewezen — wat er
  /// te veel stond doorgestreept, wat er miste onderstreept. Een cijfer zegt
  /// hoe ver je zat; dit zegt waaróm, en daar leer je iets van.
  ///
  /// Bij een letterlijk goed antwoord blijft de vergelijking weg: er valt dan
  /// niets aan te wijzen.
  List<Widget> _openTextResult(
    BuildContext context,
    QuestionView v,
    QuestionSpec spec,
  ) {
    final l10n = context.l10n;
    final typed = _collapsed(v.typedAnswer);
    final expected = _collapsed(v.expectedAnswer);
    final identical =
        normalizeAnswerText(typed) == normalizeAnswerText(expected);
    final diff = identical
        ? const <TextDiffSegment>[]
        : diffText(typed, expected);

    return [
      _resultChip(context, 1),
      if (!identical && expected.isNotEmpty) ...[
        SizedBox(height: w * 0.02),
        _answerLine(
          context,
          label: l10n.d('Jouw antwoord'),
          segments: leftSide(diff),
          markedKind: TextDiffKind.onlyLeft,
          markedColor: AppTheme.danger800,
          decoration: TextDecoration.lineThrough,
        ),
        SizedBox(height: w * 0.016),
        _answerLine(
          context,
          label: l10n.d('Het juiste antwoord'),
          segments: rightSide(diff),
          markedKind: TextDiffKind.onlyRight,
          markedColor: AppTheme.success600,
          decoration: TextDecoration.underline,
        ),
      ],
      SizedBox(height: w * 0.016),
      Text(
        // Het percentage staat naast de drempel die de auteur koos, anders is
        // "62%" een getal zonder maatstaf.
        '${l10n.d('Overeenkomst')}: ${(v.matchScore * 100).round()}%'
        '  ·  ${l10n.d('nodig')}: ${(spec.similarityThreshold * 100).round()}%',
        style: TextStyle(
          fontFamily: font,
          fontSize: w * 0.022,
          color: AppTheme.parseHexColor(
            profile.textColor,
          ).withValues(alpha: 0.6),
        ),
      ),
    ];
  }

  /// Eén regel van de correctie: een kopje met daaronder de tekst, waarin de
  /// stukken van [markedKind] gemarkeerd zijn. Bewust met een [decoration]
  /// erbij en niet alleen met kleur — wie kleuren slecht onderscheidt, moet de
  /// aanwijzing net zo goed kunnen lezen.
  Widget _answerLine(
    BuildContext context, {
    required String label,
    required List<TextDiffSegment> segments,
    required TextDiffKind markedKind,
    required Color markedColor,
    required TextDecoration decoration,
  }) {
    final textColor = AppTheme.parseHexColor(profile.textColor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: font,
            fontSize: w * 0.021,
            fontWeight: FontWeight.w600,
            color: textColor.withValues(alpha: 0.55),
          ),
        ),
        SizedBox(height: w * 0.006),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: w * 0.02,
            vertical: w * 0.014,
          ),
          decoration: BoxDecoration(
            color: markedColor.withValues(alpha: 0.08),
            border: Border.all(
              color: markedColor.withValues(alpha: 0.55),
              width: w * 0.002,
            ),
            borderRadius: BorderRadius.circular(w * 0.01),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                for (final s in segments)
                  TextSpan(
                    text: s.text,
                    style: s.kind == markedKind
                        ? TextStyle(
                            color: markedColor,
                            fontWeight: FontWeight.w700,
                            decoration: decoration,
                            decorationColor: markedColor,
                            decorationThickness: 2,
                          )
                        : TextStyle(color: textColor),
                  ),
              ],
            ),
            style: TextStyle(fontFamily: font, fontSize: w * 0.03, height: 1.3),
          ),
        ),
      ],
    );
  }

  /// Randspaties weg en dubbele spaties samentrekken, hoofdletters intact. Zo
  /// wijst de vergelijking geen verschillen aan die bij het goedrekenen ook
  /// niet meetellen.
  String _collapsed(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Het invoerveld voor een getypt antwoord.
///
/// [onChanged] null betekent spiegelen in plaats van invoeren: het
/// beamervenster toont dan wat er op het presentatorscherm getypt wordt, zodat
/// er nooit op twee schermen tegelijk in hetzelfde antwoord getypt wordt.
class _OpenAnswerField extends StatefulWidget {
  final String value;
  final String hint;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmit;
  final String fontFamily;
  final double fontSize;
  final EdgeInsets padding;
  final double radius;
  final Color textColor;
  final Color accent;

  const _OpenAnswerField({
    required this.value,
    required this.hint,
    required this.enabled,
    required this.onChanged,
    required this.onSubmit,
    required this.fontFamily,
    required this.fontSize,
    required this.padding,
    required this.radius,
    required this.textColor,
    required this.accent,
  });

  @override
  State<_OpenAnswerField> createState() => _OpenAnswerFieldState();
}

class _OpenAnswerFieldState extends State<_OpenAnswerField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _OpenAnswerField old) {
    super.didUpdateWidget(old);
    // Alleen bijstellen wanneer de waarde van búiten afwijkt — anders zou elke
    // toetsaanslag de cursor naar het begin gooien.
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
      _controller.selection = TextSelection.collapsed(
        offset: widget.value.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editable = widget.enabled && widget.onChanged != null;
    return Container(
      padding: widget.padding,
      decoration: BoxDecoration(
        color: widget.textColor.withValues(alpha: 0.05),
        border: Border.all(
          color: widget.enabled
              ? widget.accent
              : widget.textColor.withValues(alpha: 0.25),
          width: 2,
        ),
        borderRadius: BorderRadius.circular(widget.radius),
      ),
      child: TextField(
        controller: _controller,
        enabled: editable,
        autofocus: editable,
        readOnly: !editable,
        maxLines: 1,
        cursorColor: widget.accent,
        textInputAction: TextInputAction.done,
        onChanged: widget.onChanged,
        onSubmitted: (_) => widget.onSubmit?.call(),
        style: TextStyle(
          fontFamily: widget.fontFamily,
          fontSize: widget.fontSize,
          color: widget.textColor,
        ),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: widget.hint,
          hintStyle: TextStyle(
            fontFamily: widget.fontFamily,
            fontSize: widget.fontSize,
            color: widget.textColor.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}
