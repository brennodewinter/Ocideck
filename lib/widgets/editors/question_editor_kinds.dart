// Part of the question_editor library — see question_editor.dart.
// Split out for navigability (de twee soorten die geen antwoordlijst hebben);
// all imports live in the main library file.
part of 'question_editor.dart';

extension _QuestionEditorKinds on _QuestionEditorState {
  // ── Twee afbeeldingen ──────────────────────────────────────────────────────

  /// Zorg dat er precies twee antwoordplekken zijn om de beelden in te zetten.
  /// Wordt aangeroepen bij het kiezen van de soort; bestaande antwoorden blijven
  /// staan, zodat omschakelen niets weggooit.
  void _ensureImagePairSlots() {
    while (_answers.length < questionImagePairCount) {
      _answers.add(_makeCtrl(''));
      _correct.add(false);
      _images.add('');
    }
    // Precies één juiste. Zonder dat is er niets aan te wijzen — of juist alles.
    if (!_correct.take(questionImagePairCount).contains(true)) {
      _correct[0] = true;
    }
  }

  /// Welke kant nu als juist staat aangemerkt: 0 = links, 1 = rechts.
  int get _imagePairCorrectSide => _correct.length > 1 && _correct[1] ? 1 : 0;

  List<Widget> _imagePairSection(AppLocalizations l10n) {
    // De lijst kan bij het openen van een oud deck korter zijn dan twee.
    if (_answers.length < questionImagePairCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _rebuild(_ensureImagePairSlots);
        _emit();
      });
      return const [];
    }
    return [
      const SectionLabel('De twee afbeeldingen'),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          l10n.d(
            'De kijker wijst de juiste afbeelding aan. Bij presenteren wisselt links/rechts per ronde, dus benoem ze niet als "linker" en "rechter".',
          ),
          style: TextStyle(fontSize: 12, color: AppTheme.slate500),
        ),
      ),
      for (var i = 0; i < questionImagePairCount; i++) ...[
        _imageSlot(l10n, i),
        const SizedBox(height: 12),
      ],
      Text(
        l10n.d('Het juiste antwoord'),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      SegmentedButton<int>(
        segments: [
          ButtonSegment(value: 0, label: Text(l10n.d('Afbeelding 1'))),
          ButtonSegment(value: 1, label: Text(l10n.d('Afbeelding 2'))),
        ],
        selected: {_imagePairCorrectSide},
        showSelectedIcon: false,
        onSelectionChanged: (selection) {
          final side = selection.first;
          _rebuild(() {
            for (var i = 0; i < _correct.length; i++) {
              _correct[i] = i == side;
            }
          });
          _emit();
        },
      ),
      if (_images.take(questionImagePairCount).any((p) => p.trim().isEmpty))
        _warningRow(l10n.d('Kies twee afbeeldingen en markeer de juiste.')),
    ];
  }

  /// Eén afbeeldingsplek: de kiezer plus het bijschrift, dat als tekst onder het
  /// beeld verschijnt.
  Widget _imageSlot(AppLocalizations l10n, int i) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${l10n.d('Afbeelding')} ${i + 1}',
          style: TextStyle(fontSize: 12, color: AppTheme.slate500),
        ),
        const SizedBox(height: 4),
        ImagePickerBar(
          imagePath: _images[i],
          imageCaption: _answers[i].text,
          searchPaths: widget.searchPaths,
          captionBasePath: widget.captionBasePath,
          onPicked: (path, caption) => _setImage(i, path, caption: caption),
          onBrowse: () async {
            final path = await pickImageWithFeedback(
              context,
              widget.imageService,
              projectPath: widget.captionBasePath,
            );
            if (path != null) _setImage(i, path);
          },
          onPaste: () async {
            final path = await pasteImageWithFeedback(
              context,
              widget.imageService,
              projectPath: widget.captionBasePath,
            );
            if (path != null) _setImage(i, path);
          },
          onClear: _images[i].isNotEmpty ? () => _setImage(i, '') : null,
          onCaptionChanged: (caption) => _answers[i].text = caption,
        ),
      ],
    );
  }

  void _setImage(int i, String path, {String? caption}) {
    _rebuild(() => _images[i] = path);
    if (caption != null && caption.isNotEmpty) _answers[i].text = caption;
    _emit();
  }

  // ── Getypt antwoord ────────────────────────────────────────────────────────

  List<Widget> _openTextSection(AppLocalizations l10n) {
    final filled = _answers.where((c) => c.text.trim().isNotEmpty).length;
    return [
      const SectionLabel('Goed gerekende antwoorden'),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          l10n.d(
            'De kijker typt het antwoord. Elk antwoord dat je hier aanvinkt telt als goed; hoofdletters en extra spaties maken niet uit.',
          ),
          style: TextStyle(fontSize: 12, color: AppTheme.slate500),
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
      if (filled == 0 || !_correct.contains(true))
        _warningRow(l10n.d('Vink minstens één goed gerekend antwoord aan.')),
      const SizedBox(height: 12),
      _similaritySlider(l10n),
    ];
  }

  /// De drempel waarboven een getypt antwoord goed gerekend wordt. Uitgedrukt in
  /// procenten, want "0,85 Jaro-Winkler" zegt een auteur niets.
  Widget _similaritySlider(AppLocalizations l10n) {
    final percent = (_similarity * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.d('Vereiste overeenkomst met het juiste antwoord'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Text(
              '$percent%',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        Slider(
          value: _similarity.clamp(
            questionMinSimilarity,
            questionMaxSimilarity,
          ),
          min: questionMinSimilarity,
          max: questionMaxSimilarity,
          divisions:
              ((questionMaxSimilarity - questionMinSimilarity) * 100).round() ~/
              5,
          label: '$percent%',
          onChanged: (value) {
            _rebuild(() => _similarity = value);
            _emit();
          },
        ),
        Text(
          _similarity >= 0.99
              ? l10n.d('Alleen een letterlijk gelijk antwoord telt.')
              : l10n.d('Een tikfout telt nog als goed; een ander woord niet.'),
          style: TextStyle(fontSize: 12, color: AppTheme.slate500),
        ),
      ],
    );
  }

  Widget _warningRow(String message) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        const Icon(
          Icons.warning_amber_rounded,
          size: 16,
          color: AppTheme.amber700,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontSize: 12, color: AppTheme.amber700),
          ),
        ),
      ],
    ),
  );
}
