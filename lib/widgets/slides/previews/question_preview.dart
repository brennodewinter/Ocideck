part of '../slide_preview.dart';

/// Visual state of a single answer tile.
enum _OptionVisual { neutral, selected, correct, wrong, dim, authorCorrect }

/// One answer tile to render: [badge] vervangt de standaard letter (A, B, …);
/// [trailing] is een kleine feedbackregel onder de optietekst.
typedef _OptionRow = ({
  String text,
  _OptionVisual visual,
  String? badge,
  String? trailing,
});

/// Renders a question slide. In the editor (when [view] is null) it shows the
/// authoring view: the prompt plus every answer with the correct ones marked,
/// and a hint summarising how it will be presented. During a presentation
/// ([view] non-null) it shows the randomly drawn options, is tappable, and
/// colours the result once answered.
class _QuestionPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String? projectPath;
  final String font;
  final ThemeProfile profile;
  final bool presentationMode;
  final QuestionView? view;
  final ValueChanged<int>? onAnswerSelected;
  final VoidCallback? onAnswerSubmit;

  const _QuestionPreview({
    required this.slide,
    required this.w,
    required this.projectPath,
    required this.font,
    required this.profile,
    required this.presentationMode,
    required this.view,
    required this.onAnswerSelected,
    required this.onAnswerSubmit,
  });

  bool get _interactive =>
      presentationMode &&
      view != null &&
      onAnswerSelected != null &&
      !view!.locked &&
      !view!.revealed;

  @override
  Widget build(BuildContext context) {
    final spec = QuestionSpec.parse(slide.customMarkdown);
    final hasImage = slide.imagePath.isNotEmpty;
    final pad = w * 0.06;

    final body = Padding(
      padding: EdgeInsets.fromLTRB(
        pad,
        w * 0.05,
        hasImage ? w * 0.02 : pad,
        pad,
      ),
      child: _content(context, spec),
    );

    Widget content = body;
    if (hasImage) {
      final imgWidth =
          w *
          (slide.imageSize > 0 ? slide.imageSize / 100.0 : 0.40).clamp(
            0.2,
            0.6,
          );
      final gap = w * 0.03;
      content = Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: imgWidth,
            child: _imagePanel(context),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: imgWidth + gap,
            bottom: 0,
            child: body,
          ),
        ],
      );
    }

    return Container(
      color: _hexColor(profile.slideBackgroundColor),
      child: Stack(
        children: [
          Positioned.fill(child: content),
          if (view != null && view!.hasTimer)
            Positioned(top: 0, left: 0, right: 0, child: _timerBar()),
        ],
      ),
    );
  }

  Widget _imagePanel(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _resolvedImage(
          context,
          slide.imagePath,
          projectPath,
          semanticLabel: imageSemanticsLabel(context, slide.imageCaption),
        ),
        _captionOverlay(context, slide.imageCaption, w),
        // Magnify affordance — opens the detail/zoom popup.
        Positioned(
          top: w * 0.015,
          right: w * 0.015,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => showImageZoomDialog(
                context,
                imagePath: slide.imagePath,
                projectPath: projectPath,
                caption: slide.imageCaption,
              ),
              child: Padding(
                padding: EdgeInsets.all(w * 0.012),
                child: Icon(Icons.zoom_in, color: Colors.white, size: w * 0.03),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Basismaten als fractie van de slidebreedte; in [_content] vermenigvuldigd
  // met de gemeten schaal zodat alles verticaal past zónder de breedte op te
  // geven (i.t.t. een uniforme FittedBox, die ook horizontaal zou krimpen).
  static const _promptF = 0.046;
  static const _gapPromptF = 0.03;
  static const _tileVPadF = 0.02;
  static const _tileHPadF = 0.025;
  static const _badgeF = 0.044;
  static const _badgeGapF = 0.022;
  static const _optTextF = 0.03;
  static const _trailTextF = 0.022;
  static const _trailGapF = 0.008;
  static const _tileGapF = 0.018;
  static const _timerGapF = 0.02;
  static const _footerGapF = 0.02;

  /// Verzamel de te tonen opties (tekst + visuele staat + badge/feedback).
  List<_OptionRow> _collectOptions(BuildContext context, QuestionSpec spec) {
    final options = <_OptionRow>[];
    if (view != null && view!.ordering) {
      _collectOrderingPresentOptions(context, options);
    } else if (view != null) {
      for (var i = 0; i < view!.options.length; i++) {
        options.add((
          text: view!.options[i],
          visual: _presentVisual(i),
          badge: null,
          trailing: null,
        ));
      }
    } else if (spec.kind == QuestionKind.trueFalse) {
      // Auteursweergave juist/onjuist: toon beide met de juiste gemarkeerd.
      final labels = [context.l10n.d('Juist'), context.l10n.d('Onjuist')];
      final correctIdx = spec.statementIsTrue ? 0 : 1;
      for (var i = 0; i < labels.length; i++) {
        options.add((
          text: labels[i],
          visual: i == correctIdx
              ? _OptionVisual.authorCorrect
              : _OptionVisual.neutral,
          badge: null,
          trailing: null,
        ));
      }
    } else if (spec.kind == QuestionKind.ordering) {
      // Auteursweergave volgorde: de lijstvolgorde ís de juiste volgorde.
      final answers = spec.filledAnswers;
      for (var k = 0; k < answers.length; k++) {
        options.add((
          text: answers[k].text,
          visual: _OptionVisual.authorCorrect,
          badge: '${k + 1}',
          trailing: null,
        ));
      }
    } else {
      final answers = spec.filledAnswers;
      for (final a in answers) {
        options.add((
          text: a.text,
          visual: a.correct
              ? _OptionVisual.authorCorrect
              : _OptionVisual.neutral,
          badge: null,
          trailing: null,
        ));
      }
    }
    return options;
  }

  Widget _content(BuildContext context, QuestionSpec spec) {
    final accent = _hexColor(profile.accentColor);
    final textColor = _hexColor(profile.textColor);

    final options = _collectOptions(context, spec);
    final prompt = spec.prompt.isEmpty ? '—' : spec.prompt;
    final hasTimer = view != null && view!.hasTimer;
    final isMulti = view != null && view!.multi;
    // Bij meerdere-juiste: vóór onthullen een instructie + 'Bevestig'-knop.
    final showSubmit =
        isMulti && !view!.revealed && !view!.locked && _interactive;
    final hasFooter =
        (view != null && view!.revealed) || view == null || showSubmit;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth;
        final availH = constraints.maxHeight;

        // Totale inhoudshoogte bij schaal [s], op de volle breedte [availW].
        double measure(double s) {
          double h = 0;
          if (hasTimer) h += w * _timerGapF * s;
          h += measureTextHeight(
            prompt,
            w * _promptF * s,
            availW,
            lineHeight: 1.2,
            bold: true,
            fontFamily: font,
          );
          h += w * _gapPromptF * s;
          final optTextW = math.max(
            1.0,
            availW -
                w * _tileHPadF * 2 * s -
                w * _badgeF * s -
                w * _badgeGapF * s,
          );
          for (var i = 0; i < options.length; i++) {
            var textH = measureTextHeight(
              options[i].text.isEmpty ? '—' : options[i].text,
              w * _optTextF * s,
              optTextW,
              lineHeight: 1.2,
              fontFamily: font,
            );
            final trailing = options[i].trailing;
            if (trailing != null) {
              textH +=
                  w * _trailGapF * s +
                  measureTextHeight(
                    trailing,
                    w * _trailTextF * s,
                    optTextW,
                    lineHeight: 1.2,
                    fontFamily: font,
                  );
            }
            final rowH = math.max(w * _badgeF * s, textH);
            h += rowH + w * _tileVPadF * 2 * s;
            if (i < options.length - 1) h += w * _tileGapF * s;
          }
          if (hasFooter) {
            h += w * _footerGapF * s + w * _optTextF * 1.4 * s;
          }
          return h;
        }

        final scale = tightenVerticalFitScale(
          scale: 1.0,
          availH: availH,
          measure: measure,
        );

        final column = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasTimer) SizedBox(height: w * _timerGapF * scale),
            _md(
              context,
              prompt,
              TextStyle(
                fontFamily: font,
                fontSize: w * _promptF * scale,
                fontWeight: FontWeight.w600,
                color: textColor,
                height: 1.2,
              ),
              linkColor: accent,
            ),
            SizedBox(height: w * _gapPromptF * scale),
            for (var i = 0; i < options.length; i++) ...[
              _optionTile(
                context,
                options[i].text,
                i,
                options[i].visual,
                scale,
                badge: options[i].badge,
                trailing: options[i].trailing,
              ),
              if (i < options.length - 1)
                SizedBox(height: w * _tileGapF * scale),
            ],
            if (showSubmit) ...[
              SizedBox(height: w * _footerGapF * scale),
              _submitRow(context, scale),
            ],
            if (view != null && view!.revealed) ...[
              SizedBox(height: w * _footerGapF * scale),
              _resultChip(context, scale),
            ],
            if (view == null) ...[
              SizedBox(height: w * _footerGapF * scale),
              _authorHint(context, spec, scale),
            ],
          ],
        );

        // Vangnet: bij normale grootte past de gemeten schaal al, dus de
        // FittedBox doet niets (volle breedte blijft). Alleen in extreem kleine
        // miniaturen — waar de leesbaarheidsondergrens het verder verkleinen
        // tegenhoudt — krimpt dit het geheel zodat er nooit overflow ontstaat.
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: SizedBox(width: availW, child: column),
        );
      },
    );
  }

  /// Opties van een volgorde-vraag tijdens presenteren. Vóór onthullen: de
  /// geschudde lijst met een •-badge, of het gekozen plaatsnummer na aantikken.
  /// Ná onthullen: de rijen herschikt naar de júiste volgorde, met het
  /// positienummer als badge; groen waar de kijker het item op die plek had,
  /// rood met de eigen (foute) plek als feedbackregel eronder.
  void _collectOrderingPresentOptions(
    BuildContext context,
    List<_OptionRow> options,
  ) {
    final v = view!;
    if (!v.revealed) {
      for (var i = 0; i < v.options.length; i++) {
        final pos = v.selectedPositionOf(i);
        options.add((
          text: v.options[i],
          visual: pos != null ? _OptionVisual.selected : _OptionVisual.neutral,
          badge: pos != null ? '$pos' : '•',
          trailing: null,
        ));
      }
      return;
    }
    for (var k = 0; k < v.correctIndices.length; k++) {
      final optIdx = v.correctIndices[k];
      final userPos = v.selectedPositionOf(optIdx);
      final placedRight = userPos == k + 1;
      options.add((
        text: v.options[optIdx],
        visual: placedRight ? _OptionVisual.correct : _OptionVisual.wrong,
        badge: '${k + 1}',
        trailing: placedRight
            ? null
            : '${context.l10n.d('Jouw volgorde')}: ${userPos ?? '—'}',
      ));
    }
  }

  _OptionVisual _presentVisual(int i) {
    final v = view!;
    if (!v.revealed) {
      return v.isSelected(i) ? _OptionVisual.selected : _OptionVisual.neutral;
    }
    if (v.isCorrect(i)) return _OptionVisual.correct;
    if (v.isSelected(i)) return _OptionVisual.wrong;
    return _OptionVisual.dim;
  }

  /// Instructie + 'Bevestig'-knop voor een meervoudige vraag (meerdere-juiste
  /// of volgorde). Bij volgorde kan er pas bevestigd worden als álle opties een
  /// plek hebben.
  Widget _submitRow(BuildContext context, double scale) {
    final l10n = context.l10n;
    final accent = _hexColor(profile.accentColor);
    final textColor = _hexColor(profile.textColor);
    final canSubmit =
        onAnswerSubmit != null &&
        (view!.ordering ? view!.orderComplete : view!.hasSelection);
    return Row(
      children: [
        Expanded(
          child: Text(
            view!.ordering
                ? l10n.d('Tik de antwoorden aan in de juiste volgorde')
                : l10n.d('Selecteer alle juiste antwoorden'),
            style: TextStyle(
              fontFamily: font,
              fontSize: w * 0.024 * scale,
              color: textColor.withValues(alpha: 0.7),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(width: w * 0.02 * scale),
        Opacity(
          opacity: canSubmit ? 1 : 0.4,
          child: Material(
            color: accent,
            borderRadius: BorderRadius.circular(w * 0.012 * scale),
            child: InkWell(
              borderRadius: BorderRadius.circular(w * 0.012 * scale),
              onTap: canSubmit ? onAnswerSubmit : null,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.03 * scale,
                  vertical: w * 0.018 * scale,
                ),
                child: Text(
                  l10n.d('Bevestig'),
                  style: TextStyle(
                    fontFamily: font,
                    fontSize: w * 0.028 * scale,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _optionTile(
    BuildContext context,
    String text,
    int index,
    _OptionVisual visual,
    double scale, {
    String? badge,
    String? trailing,
  }) {
    const green = AppTheme.success600;
    const red = AppTheme.danger800;
    final accent = _hexColor(profile.accentColor);
    final textColor = _hexColor(profile.textColor);

    Color border;
    Color fill;
    Color fg = textColor;
    IconData? icon;
    double opacity = 1;
    switch (visual) {
      case _OptionVisual.neutral:
        border = textColor.withValues(alpha: 0.25);
        fill = textColor.withValues(alpha: 0.04);
      case _OptionVisual.selected:
        border = accent;
        fill = accent.withValues(alpha: 0.16);
      case _OptionVisual.correct:
        border = green;
        fill = green.withValues(alpha: 0.22);
        icon = Icons.check;
        fg = textColor;
      case _OptionVisual.wrong:
        border = red;
        fill = red.withValues(alpha: 0.22);
        icon = Icons.close;
      case _OptionVisual.dim:
        border = textColor.withValues(alpha: 0.15);
        fill = textColor.withValues(alpha: 0.02);
        opacity = 0.55;
      case _OptionVisual.authorCorrect:
        border = green.withValues(alpha: 0.7);
        fill = green.withValues(alpha: 0.14);
        icon = Icons.check;
    }

    final tile = Opacity(
      opacity: opacity,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: w * _tileHPadF * scale,
          vertical: w * _tileVPadF * scale,
        ),
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: border, width: w * 0.0022 * scale),
          borderRadius: BorderRadius.circular(w * 0.012 * scale),
        ),
        child: Row(
          children: [
            // De badge links toont normaal de letter (A, B, C, …) en ná het
            // antwoorden het ✓/✗. Bij een volgorde-vraag toont hij het
            // positienummer (of •). Hij staat er altijd en is altijd even
            // breed, zodat de tekst rechts de volle resterende breedte houdt —
            // geen reflow bij het aanklikken.
            Container(
              width: w * _badgeF * scale,
              height: w * _badgeF * scale,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: border.withValues(alpha: 0.18),
              ),
              child: badge != null
                  ? Text(
                      badge,
                      style: TextStyle(
                        fontFamily: font,
                        fontSize: w * 0.024 * scale,
                        fontWeight: FontWeight.w700,
                        color: border,
                      ),
                    )
                  : icon == null
                  ? Text(
                      String.fromCharCode(65 + index), // A, B, C, …
                      style: TextStyle(
                        fontFamily: font,
                        fontSize: w * 0.024 * scale,
                        fontWeight: FontWeight.w700,
                        color: border,
                      ),
                    )
                  : Icon(icon, color: border, size: w * 0.03 * scale),
            ),
            SizedBox(width: w * _badgeGapF * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _md(
                    context,
                    text,
                    TextStyle(
                      fontFamily: font,
                      fontSize: w * _optTextF * scale,
                      color: fg,
                      height: 1.2,
                    ),
                    linkColor: accent,
                  ),
                  if (trailing != null) ...[
                    SizedBox(height: w * _trailGapF * scale),
                    Text(
                      trailing,
                      style: TextStyle(
                        fontFamily: font,
                        fontSize: w * _trailTextF * scale,
                        fontWeight: FontWeight.w600,
                        color: border,
                        height: 1.2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (_interactive) {
      return InkWell(
        borderRadius: BorderRadius.circular(w * 0.012),
        onTap: () => onAnswerSelected!(index),
        child: tile,
      );
    }
    return tile;
  }

  Widget _timerBar() {
    final v = view!;
    final total = (v.totalSeconds * 1000).clamp(1, 1 << 30);
    final fraction = (v.remainingMs / total).clamp(0.0, 1.0);
    final low = fraction < 0.25;
    return SizedBox(
      height: w * 0.012,
      child: Stack(
        children: [
          Container(color: Colors.black.withValues(alpha: 0.15)),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fraction,
            child: Container(
              color: low ? AppTheme.danger800 : _hexColor(profile.accentColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultChip(BuildContext context, double scale) {
    final v = view!;
    final correct = v.result == QuestionResult.correct;
    final color = correct ? AppTheme.success600 : AppTheme.danger800;
    final label = correct ? 'Goed!' : 'Helaas, fout';
    // Fout + niet vergrendeld = retry-modus: een klik start een nieuwe poging.
    final retryPending =
        v.revealed && v.result == QuestionResult.wrong && !v.locked;
    return Row(
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: w * 0.02 * scale,
            vertical: w * 0.01 * scale,
          ),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(w * 0.01 * scale),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                correct ? Icons.check : Icons.close,
                color: Colors.white,
                size: w * 0.028 * scale,
              ),
              SizedBox(width: w * 0.01 * scale),
              Text(
                context.l10n.d(label),
                style: TextStyle(
                  fontFamily: font,
                  fontSize: w * 0.026 * scale,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        if (retryPending) ...[
          SizedBox(width: w * 0.018 * scale),
          Icon(
            Icons.replay,
            size: w * 0.026 * scale,
            color: _hexColor(profile.textColor).withValues(alpha: 0.7),
          ),
          SizedBox(width: w * 0.008 * scale),
          Flexible(
            child: Text(
              context.l10n.d('Klik om opnieuw te proberen'),
              style: TextStyle(
                fontFamily: font,
                fontSize: w * 0.024 * scale,
                color: _hexColor(profile.textColor).withValues(alpha: 0.7),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  Widget _authorHint(BuildContext context, QuestionSpec spec, double scale) {
    final l10n = context.l10n;
    final textColor = _hexColor(profile.textColor).withValues(alpha: 0.6);
    final parts = <String>[
      '${spec.optionCount} ${l10n.d('van')} ${spec.answers.where((a) => a.text.trim().isNotEmpty).length} ${l10n.d('opties worden willekeurig getoond')}',
      if (spec.timeLimitSeconds > 0)
        '${spec.timeLimitSeconds}s ${l10n.d('antwoordtijd')}',
      spec.onWrong == QuestionOnWrong.retry
          ? l10n.d('bij fout: opnieuw proberen')
          : l10n.d('bij fout: door, niet opnieuw'),
    ];
    return Row(
      children: [
        Icon(Icons.info_outline, size: w * 0.024 * scale, color: textColor),
        SizedBox(width: w * 0.012 * scale),
        Expanded(
          child: Text(
            parts.join('  ·  '),
            style: TextStyle(
              fontFamily: font,
              fontSize: w * 0.022 * scale,
              color: textColor,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
