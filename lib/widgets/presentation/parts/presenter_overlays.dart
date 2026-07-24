// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability; all imports live in the main library file.
part of '../fullscreen_presenter.dart';

/// De regels van het sneltoets-overzicht: links het toetsopschrift, rechts wat
/// het doet.
///
/// Top-level en geen lid van de extension: het is enkel tekst, en de
/// klasse-plafondratchet telt élk extension-lid mee bij
/// _FullscreenPresenterState.
List<(String, String)> _helpOverlayRows(AppLocalizations l10n) => [
  (
    '→ · ${l10n.d('spatie')} · ${l10n.d('klik')}',
    l10n.d('Volgende slide of pagina'),
  ),
  ('←', l10n.d('Vorige slide of pagina')),
  ('${l10n.d('cijfers')} + Enter', l10n.d('Naar slidenummer')),
  ('Home · End', l10n.d('Eerste · laatste slide')),
  ('G', l10n.d('Slide-overzicht (pijltjes + Enter)')),
  ('P', l10n.d('Presenter view (notities, klok)')),
  // De binding is `control || meta` (presenter_keys.dart), dus stond hier
  // voor Mac-gebruikers het verkeerde: Cmd+N werkt ook. Nu uit dezelfde
  // bron als elke andere sneltoets in de app (#803).
  ('N · ${shortcutLabel(l10n, 'N')}', l10n.d('Mijn notities aan/uit')),
  ('S', l10n.d('Scherm wisselen (meerdere schermen)')),
  ('B · W', l10n.d('Zwart · wit scherm')),
  ('D · T · Shift+E', l10n.d('Pen · markeerstift · gum')),
  ('E', l10n.d('Tabel bewerken (op tabeldia)')),
  ('X · C', l10n.d('Laser · annotaties wissen')),
  ('K', l10n.d('Doeltijd / aftellen instellen (MMSS)')),
  ('R', l10n.d('Tijd & oefenrun resetten')),
  ('A', l10n.d('Automatische modus aan/uit')),
  ('L', l10n.d('Herhalen (loop) aan/uit')),
  ('M', l10n.d('Na media automatisch doorgaan')),
  ('H', l10n.d('Deze legenda')),
  ('Esc · ${shortcutLabel(l10n, 'W')}', l10n.d('Terug / afsluiten')),
];

extension _PresenterOverlays on _FullscreenPresenterState {
  String _fmtClock(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _fmtElapsed(Duration d) {
    final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$mm:$ss' : '$mm:$ss';
  }

  /// Resterende tijd, met minteken zodra je over de doeltijd gaat.
  String _fmtRemaining(Duration d) {
    final body = _fmtElapsed(d.abs());
    return d.isNegative ? '-$body' : body;
  }

  /// Badge met het getypte slidenummer ("→ 12 / 28  · Enter").
  Widget _buildTypedBadge(int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.blue400, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.south_east, color: AppTheme.blue400, size: 20),
          const SizedBox(width: 10),
          Text(
            '$_typed / $total',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            context.l10n.d('Enter'),
            style: const TextStyle(
              color: PresenterPalette.textMuted,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  /// Badge tijdens het invoeren van de doeltijd ("Doeltijd 20:00 · Enter").
  /// Cijfers schuiven van rechts in als MM:SS (zoals een magnetron).
  Widget _buildTargetBadge() {
    final padded = _targetTyped.padLeft(4, '0');
    final preview = '${padded.substring(0, 2)}:${padded.substring(2)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.amber500, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, color: AppTheme.amber500, size: 20),
          const SizedBox(width: 10),
          Text(
            preview,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${context.l10n.d('Doeltijd')} · ${context.l10n.d('Enter')} · '
            '0 = ${context.l10n.d('uit')}',
            style: const TextStyle(
              color: PresenterPalette.textMuted,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  /// Sneltoets-overzicht (cheatsheet).
  Widget _buildHelpOverlay() {
    final l10n = context.l10n;
    final rows = _helpOverlayRows(l10n);
    return GestureDetector(
      onTap: _toggleHelp,
      child: Container(
        color: Colors.black.withValues(alpha: 0.85),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 460,
            maxHeight: MediaQuery.of(context).size.height - 48,
          ),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: PresenterPalette.bg2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: PresenterPalette.surface3),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.keyboard_outlined,
                        color: Colors.white70,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          l10n.d('Toetsenlegenda'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  for (final (keys, desc) in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 150,
                            child: Text(
                              keys,
                              style: const TextStyle(
                                color: AppTheme.blue400,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              desc,
                              style: const TextStyle(
                                color: PresenterPalette.text,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      l10n.d('Klik of druk op H / Esc om te sluiten'),
                      style: const TextStyle(
                        color: PresenterPalette.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Vol-vlak zwart/wit scherm dat met een klik weer verdwijnt.
  Widget _blankFill() {
    return GestureDetector(
      onTap: () => _rebuild(() => _blank = _Blank.none),
      child: Container(
        color: _blank == _Blank.white ? Colors.white : Colors.black,
      ),
    );
  }

  /// Eén tijdwaarde met bijschrift voor de klokbalk.
  Widget _metric(
    String label,
    String value, {
    Color? color,
    CrossAxisAlignment align = CrossAxisAlignment.start,
    double size = 24,
  }) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: PresenterPalette.textMuted,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color ?? Colors.white,
            fontSize: size,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _buildClockBar() {
    final l10n = context.l10n;
    final elapsed = _rehearsal.elapsed;
    final remaining = _rehearsal.remaining;
    final slideElapsed = _rehearsal.currentSlideElapsed;
    final overtime = remaining != null && remaining.isNegative;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: PresenterPalette.bg2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PresenterPalette.surface2),
      ),
      child: Column(
        children: [
          // Bovenrij: verstreken tijd, knoppen, wandklok.
          Row(
            children: [
              Expanded(
                child: _metric(l10n.d('Verstreken'), _fmtElapsed(elapsed)),
              ),
              IconButton(
                tooltip: l10n.d('Doeltijd / aftellen (K)'),
                onPressed: _beginTargetInput,
                icon: const Icon(Icons.timer_outlined, size: 18),
                color: PresenterPalette.textMuted,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: l10n.d('Tijd resetten (R)'),
                onPressed: _resetTimer,
                icon: const Icon(Icons.restart_alt, size: 18),
                color: PresenterPalette.textMuted,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              _metric(
                l10n.d('Klok'),
                _fmtClock(DateTime.now()),
                color: Colors.white70,
                align: CrossAxisAlignment.end,
              ),
            ],
          ),
          const Divider(height: 18, color: PresenterPalette.surface2),
          // Onderrij: aftelling (resterend/over) en tijd op huidige slide.
          Row(
            children: [
              Expanded(
                child: _metric(
                  overtime ? l10n.d('Over de tijd') : l10n.d('Resterend'),
                  remaining == null ? '–:––' : _fmtRemaining(remaining),
                  color: remaining == null
                      ? PresenterPalette.textMuted
                      : (overtime
                            ? AppTheme.danger500
                            : PresenterPalette.laserGreen),
                  size: 20,
                ),
              ),
              _metric(
                l10n.d('Deze slide'),
                _fmtElapsed(slideElapsed),
                color: Colors.white70,
                align: CrossAxisAlignment.end,
                size: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresenterControls(int total) {
    final l10n = context.l10n;
    final richTextPlan = _richTextPlanFor(_currentSlide);
    final richTextPages = richTextPlan?.pageCount ?? 1;
    final hasRichTextPages = richTextPages > 1;
    return Row(
      children: [
        _NavButton(
          icon: Icons.chevron_left,
          onTap: _index > 0 || _richTextPage > 0 ? _prev : null,
        ),
        const SizedBox(width: 8),
        _NavButton(
          icon: Icons.chevron_right,
          onTap:
              _index < total - 1 ||
                  (hasRichTextPages && _richTextPage < richTextPages - 1)
              ? _next
              : null,
        ),
        if (_displays.length > 1) ...[
          const SizedBox(width: 8),
          Tooltip(
            message: l10n.d('Wissel scherm (S)'),
            child: _NavButton(
              icon: Icons.screen_share_outlined,
              onTap: _cycleDisplay,
            ),
          ),
        ],
        const SizedBox(width: 16),
        Text(
          hasRichTextPages
              ? '${l10n.d('Slide')} ${_index + 1} / $total'
                    ' · ${l10n.d('Pagina')} ${_richTextPage + 1} / $richTextPages'
              : '${l10n.d('Slide')} ${_index + 1} / $total',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            l10n.d(
              _displays.length > 1
                  ? 'P publiek · H legenda · S scherm · G overzicht · B/W zwart/wit · R tijd · Esc stop'
                  : 'P publiek · H legenda · G overzicht · B/W zwart/wit · R tijd · Esc stop',
            ),
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: PresenterPalette.textMuted, fontSize: 11),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: l10n.d('Afsluiten (Escape)'),
          onPressed: _exit,
          icon: const Icon(Icons.close),
          color: Colors.white,
          style: IconButton.styleFrom(backgroundColor: Colors.black45),
        ),
      ],
    );
  }

  Widget _buildGridOverlay() {
    final l10n = context.l10n;
    final total = widget.slides.length;
    return Container(
      color: Colors.black.withValues(alpha: 0.94),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 12),
              child: Row(
                children: [
                  Text(
                    l10n.d('Slide-overzicht'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${l10n.d('pijltjes + Enter of klik om te springen')} · $total ${l10n.t('slides')}',
                    style: const TextStyle(
                      color: PresenterPalette.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: l10n.d('Sluiten (G of Esc)'),
                    onPressed: _toggleGrid,
                    icon: const Icon(Icons.close),
                    color: Colors.white,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white10,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (_, constraints) {
                  // Mik op tegels van ~260px breed, tussen 2 en 6 kolommen.
                  const hPad = 24.0, spacing = 16.0;
                  const aspect = 16 / 10.4; // slide + nummerregel
                  final cols = (constraints.maxWidth ~/ 260).clamp(2, 6);
                  // Maten onthouden voor pijltjesnavigatie + auto-scroll.
                  _gridCols = cols;
                  final tileW =
                      (constraints.maxWidth - hPad * 2 - spacing * (cols - 1)) /
                      cols;
                  _gridRowExtent = tileW / aspect + spacing;
                  return GridView.builder(
                    controller: _gridScroll,
                    padding: const EdgeInsets.fromLTRB(hPad, 0, hPad, 24),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      crossAxisSpacing: spacing,
                      mainAxisSpacing: spacing,
                      childAspectRatio: aspect,
                    ),
                    itemCount: total,
                    itemBuilder: (_, i) => _buildGridTile(i),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridTile(int i) {
    final isCurrent = i == _index; // de slide die nu getoond wordt
    final isCursor = i == _gridCursor; // de toetsenbordcursor

    // Cursor wint qua markering (witte rand + gloed); de huidige slide krijgt
    // anders een accentrand zodat je beide posities ziet.
    final Color borderColor;
    final double borderWidth;
    if (isCursor) {
      borderColor = Colors.white;
      borderWidth = 3;
    } else if (isCurrent) {
      borderColor = AppTheme.blue400;
      borderWidth = 2;
    } else {
      borderColor = PresenterPalette.surface4;
      borderWidth = 1;
    }

    return GestureDetector(
      onTap: () => _jumpTo(i),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setGridCursor(i),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor, width: borderWidth),
                  boxShadow: isCursor
                      ? [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.25),
                            blurRadius: 16,
                          ),
                        ]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: SlidePreviewWidget(
                      slide: widget.slides[i],
                      projectPath: widget.projectPath,
                      themeProfile: widget.themeProfile,
                      cockpitColorScheme: widget.cockpitColorScheme,
                      allowRemoteMedia: widget.allowRemoteMedia,
                      tlp: widget.tlp,
                      organization: widget.organization,
                      showClassificationWatermark:
                          widget.showClassificationWatermark,
                      scopeCia: deckScopeCiaIndex(widget.slides),
                      reportLanguage: widget.reportLanguage,
                      fitScaleOverride: sharedSplitFitScale(
                        widget.slides,
                        i,
                        widget.themeProfile,
                        widget.themeProfile.fontFamily,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${i + 1}',
                  style: TextStyle(
                    color: (isCursor || isCurrent)
                        ? Colors.white
                        : PresenterPalette.textMuted,
                    fontSize: 12,
                    fontWeight: (isCursor || isCurrent)
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
                if (isCurrent) ...[
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.play_arrow_rounded,
                    size: 13,
                    color: AppTheme.blue400,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
