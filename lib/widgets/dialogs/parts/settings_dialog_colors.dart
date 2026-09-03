// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (colour + logo sections); all imports live in the main
// library file. Instance methods relocate verbatim into an extension on
// _SettingsDialogState — same library, same members, no behaviour change.
part of '../settings_dialog.dart';

extension _SettingsColors on _SettingsDialogState {
  /// De kleuren die zowel een document als een presentatie dragen: het papier,
  /// de tekst, het accent en alles wat in beide vlakken voorkomt — checklists,
  /// tabellen, broncode en de severity-banden.
  ///
  /// Wat híer staat geldt overal. De dia-eigen kleuren (titelbalk,
  /// sectieachtergrond) staan bewust apart in [_slideColorChildren]: stonden ze
  /// in één lijst, dan is aan niets te zien welke kleur een document raakt en
  /// welke alleen een dia.
  List<Widget> _generalColorChildren() {
    final l10n = context.l10n;
    final contrast = _themeContrastByField();
    return [
      _themeColorAnchor(
        'slideBackgroundColor',
        _colorSetting(
          l10n.d('Achtergrond'),
          _themeProfile.slideBackgroundColor,
          (v) =>
              _themeProfile = _themeProfile.copyWith(slideBackgroundColor: v),
        ),
      ),
      const SizedBox(height: 12),
      _themeColorAnchor(
        'textColor',
        _colorWithContrastWarning(
          _colorSetting(
            l10n.d('Tekst'),
            _themeProfile.textColor,
            (v) => _themeProfile = _themeProfile.copyWith(textColor: v),
          ),
          'textColor',
          contrast,
        ),
      ),
      const SizedBox(height: 12),
      _themeColorAnchor(
        'accentColor',
        _colorWithContrastWarning(
          _colorSetting(
            l10n.d('Accent / bullets'),
            _themeProfile.accentColor,
            (v) => _themeProfile = _themeProfile.copyWith(accentColor: v),
          ),
          'accentColor',
          contrast,
        ),
      ),
      const SizedBox(height: 12),
      _settingFieldRow(
        context,
        label: Text(
          l10n.d('Opsommingsteken'),
          style: const TextStyle(fontSize: 13),
        ),
        control: SegmentedButton<BulletMarker>(
          segments: [
            ButtonSegment(
              value: BulletMarker.dot,
              icon: const Icon(Icons.fiber_manual_record, size: 12),
              label: Text(l10n.d('Stip')),
            ),
            ButtonSegment(
              value: BulletMarker.paw,
              icon: const Icon(Icons.pets, size: 16),
              label: Text(l10n.d('Pootje')),
            ),
          ],
          selected: {_themeProfile.bulletMarker},
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          onSelectionChanged: (selection) => _rebuild(() {
            _themeProfile = _themeProfile.copyWith(
              bulletMarker: selection.first,
            );
            _profileTouched = true;
          }),
        ),
      ),
      ..._checklistColorSettings(contrast),
      ..._tableColorSettings(contrast),
      ..._codeColorSettings(contrast),
      ..._severityColorSettings(),
    ];
  }

  /// De kleuren die alléén een dia raakt: de titelbalk en de sectieachtergrond.
  /// Een document kent geen titeldia, dus deze drie velden hebben daar niets te
  /// zoeken.
  List<Widget> _slideColorChildren() {
    final l10n = context.l10n;
    final contrast = _themeContrastByField();
    return [
      _themeColorAnchor(
        'titleBackgroundColor',
        _colorSetting(
          l10n.d('Titelachtergrond'),
          _themeProfile.titleBackgroundColor,
          (v) =>
              _themeProfile = _themeProfile.copyWith(titleBackgroundColor: v),
        ),
      ),
      const SizedBox(height: 12),
      _themeColorAnchor(
        'titleTextColor',
        _colorWithContrastWarning(
          _colorSetting(
            l10n.d('Titeltekst'),
            _themeProfile.titleTextColor,
            (v) => _themeProfile = _themeProfile.copyWith(titleTextColor: v),
          ),
          // The analyser checks the title colour against both the title band and
          // (via a section probe slide) the section background; either failing
          // surfaces here.
          'titleTextColor',
          contrast,
        ),
      ),
      const SizedBox(height: 12),
      _themeColorAnchor(
        'sectionBackgroundColor',
        _colorSetting(
          l10n.d('Sectieachtergrond'),
          _themeProfile.sectionBackgroundColor,
          (v) =>
              _themeProfile = _themeProfile.copyWith(sectionBackgroundColor: v),
        ),
      ),
    ];
  }

  /// Severity colour tokens for finding cards / CVSS badges (FIRST bands). The
  /// band labels reuse the shared findings-summary strings so they never drift
  /// (PENTEST_MIAUW §11).
  List<Widget> _severityColorSettings() {
    final l10n = context.l10n;
    return [
      const SizedBox(height: 24),
      _sectionTitle(l10n.d('Severity (bevindingen)')),
      _themeColorAnchor(
        'severityCriticalColor',
        _colorSetting(
          l10n.d('Kritiek'),
          _themeProfile.severityCriticalColor,
          (v) =>
              _themeProfile = _themeProfile.copyWith(severityCriticalColor: v),
        ),
      ),
      const SizedBox(height: 12),
      _themeColorAnchor(
        'severityHighColor',
        _colorSetting(
          l10n.d('Hoog'),
          _themeProfile.severityHighColor,
          (v) => _themeProfile = _themeProfile.copyWith(severityHighColor: v),
        ),
      ),
      const SizedBox(height: 12),
      _themeColorAnchor(
        'severityMediumColor',
        _colorSetting(
          l10n.d('Middel'),
          _themeProfile.severityMediumColor,
          (v) => _themeProfile = _themeProfile.copyWith(severityMediumColor: v),
        ),
      ),
      const SizedBox(height: 12),
      _themeColorAnchor(
        'severityLowColor',
        _colorSetting(
          l10n.d('Laag'),
          _themeProfile.severityLowColor,
          (v) => _themeProfile = _themeProfile.copyWith(severityLowColor: v),
        ),
      ),
      const SizedBox(height: 12),
      _themeColorAnchor(
        'severityNoneColor',
        _colorSetting(
          l10n.d('Informatief'),
          _themeProfile.severityNoneColor,
          (v) => _themeProfile = _themeProfile.copyWith(severityNoneColor: v),
        ),
      ),
    ];
  }

  /// Deck-wide default activation duration for animated slide types (timeline,
  /// cockpit). A slide inherits this unless it sets its own duration.
  List<Widget> _animationSettings() {
    final l10n = context.l10n;
    final ms = clampThemeAnimationDuration(_themeProfile.animationDurationMs);
    final seconds = ms / 1000;
    return [
      const SizedBox(height: 12),
      Row(
        children: [
          Icon(Icons.timer_outlined, size: 18, color: AppTheme.slate500),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.d('Activatieduur'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '${seconds.toStringAsFixed(1)}s',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.slate500,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      Slider(
        min: kThemeMinAnimationDurationMs.toDouble(),
        max: kThemeMaxAnimationDurationMs.toDouble(),
        divisions:
            (kThemeMaxAnimationDurationMs - kThemeMinAnimationDurationMs) ~/
            200,
        label: '${seconds.toStringAsFixed(1)}s',
        value: ms.toDouble(),
        onChanged: (value) => _rebuild(() {
          _themeProfile = _themeProfile.copyWith(
            animationDurationMs: clampThemeAnimationDuration(
              (value / 100).round() * 100,
            ),
          );
          _profileTouched = true;
        }),
      ),
    ];
  }

  List<Widget> _checklistColorSettings(
    Map<String, SlideQualityIssue> contrast,
  ) {
    final l10n = context.l10n;
    return [
      const SizedBox(height: 24),
      _sectionTitle(l10n.d('Checklist')),
      _themeColorAnchor(
        'checklistCheckedColor',
        _colorWithContrastWarning(
          _colorSetting(
            l10n.d('Afgevinkt'),
            _themeProfile.checklistCheckedColor,
            (v) => _themeProfile = _themeProfile.copyWith(
              checklistCheckedColor: v,
            ),
          ),
          'checklistCheckedColor',
          contrast,
        ),
      ),
      const SizedBox(height: 12),
      _themeColorAnchor(
        'checklistUncheckedColor',
        _colorWithContrastWarning(
          _colorSetting(
            l10n.d('Niet afgevinkt'),
            _themeProfile.checklistUncheckedColor,
            (v) => _themeProfile = _themeProfile.copyWith(
              checklistUncheckedColor: v,
            ),
          ),
          'checklistUncheckedColor',
          contrast,
        ),
      ),
      const SizedBox(height: 6),
      SwitchListTile(
        value: _themeProfile.checklistStrikeThrough,
        onChanged: (value) => _rebuild(() {
          _themeProfile = _themeProfile.copyWith(checklistStrikeThrough: value);
          _profileTouched = true;
        }),
        title: Text(
          l10n.d('Afgevinkte tekst doorhalen'),
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          l10n.d('Toont een streep door voltooide checklistitems.'),
          style: TextStyle(fontSize: 11, color: AppTheme.slate400),
        ),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
      ),
    ];
  }

  /// De tabelkleuren en de tabelstijl. Los van de checklistkleuren waar ze
  /// eerst bij in stonden: met de zes stijlvelden erbij liep dat blok over de
  /// methodelengte-grens heen, en het zijn twee onderwerpen.
  List<Widget> _tableColorSettings(Map<String, SlideQualityIssue> contrast) {
    final l10n = context.l10n;
    return [
      const SizedBox(height: 24),
      _sectionTitle(l10n.d('Tabel')),
      _themeColorAnchor(
        'tableTextColor',
        _colorWithContrastWarning(
          _colorSetting(
            l10n.d('Tabeltekst'),
            _themeProfile.tableTextColor,
            (v) => _themeProfile = _themeProfile.copyWith(tableTextColor: v),
          ),
          'tableTextColor',
          contrast,
        ),
      ),
      const SizedBox(height: 12),
      _themeColorAnchor(
        'tableHeaderTextColor',
        _colorWithContrastWarning(
          _colorSetting(
            l10n.d('Tabel koptekst'),
            _themeProfile.tableHeaderTextColor,
            (v) =>
                _themeProfile = _themeProfile.copyWith(tableHeaderTextColor: v),
          ),
          'tableHeaderTextColor',
          contrast,
        ),
      ),
      const SizedBox(height: 12),
      _themeColorAnchor(
        'tableHeaderBackgroundColor',
        _colorSetting(
          l10n.d('Tabel kopachtergrond'),
          _themeProfile.tableHeaderBackgroundColor,
          (v) => _themeProfile = _themeProfile.copyWith(
            tableHeaderBackgroundColor: v,
          ),
        ),
      ),
      const SizedBox(height: 12),
      // Feature 5: tabel look-and-feel — zebrastrepen, randstijl, celopvulling,
      // accentkoprand. Huisstijl die voor alle tabellen geldt.
      _themeColorAnchor(
        'tableBorderColor',
        _colorSetting(
          l10n.d('Tabel randkleur'),
          _themeProfile.tableBorderColor,
          (v) => _themeProfile = _themeProfile.copyWith(tableBorderColor: v),
        ),
      ),
      const SizedBox(height: 12),
      _themeColorAnchor(
        'tableZebraColor',
        _colorSetting(
          l10n.d('Tabel zebrakleur'),
          _themeProfile.tableZebraColor,
          (v) => _themeProfile = _themeProfile.copyWith(tableZebraColor: v),
        ),
      ),
      const SizedBox(height: 12),
      _tableStyleControls(l10n),
    ];
  }

  List<Widget> _codeColorSettings(Map<String, SlideQualityIssue> contrast) {
    final l10n = context.l10n;
    return [
      const SizedBox(height: 24),
      _sectionTitle(l10n.d('Broncode')),
      _themeColorAnchor(
        'codeBackgroundColor',
        _colorSetting(
          l10n.d('Broncode achtergrond'),
          _themeProfile.codeBackgroundColor,
          (v) => _themeProfile = _themeProfile.copyWith(codeBackgroundColor: v),
        ),
      ),
      const SizedBox(height: 12),
      _themeColorAnchor(
        'codeTextColor',
        _colorWithContrastWarning(
          _colorSetting(
            l10n.d('Broncode tekst'),
            _themeProfile.codeTextColor,
            (v) => _themeProfile = _themeProfile.copyWith(codeTextColor: v),
          ),
          'codeTextColor',
          contrast,
        ),
      ),
      const SizedBox(height: 6),
      SwitchListTile(
        value: _themeProfile.codeHighlightSyntax,
        onChanged: (v) => _rebuild(() {
          _themeProfile = _themeProfile.copyWith(codeHighlightSyntax: v);
          _profileTouched = true;
        }),
        title: Text(
          l10n.d('Syntaxkleuring'),
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          l10n.d(
            'Uit = alles in één kleur (bijv. groen op zwart voor een CRT-scherm).',
          ),
          style: TextStyle(fontSize: 11, color: AppTheme.slate400),
        ),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue:
            AppSettings.codeFonts.contains(_themeProfile.codeFontFamily)
            ? _themeProfile.codeFontFamily
            : 'monospace',
        decoration: InputDecoration(
          labelText: l10n.d('Broncode lettertype'),
          isDense: true,
        ),
        items: [
          for (final f in AppSettings.codeFonts)
            DropdownMenuItem(
              value: f,
              child: Text(
                f == 'monospace' ? l10n.d('Systeem (monospace)') : f,
                style: TextStyle(fontFamily: f),
              ),
            ),
        ],
        onChanged: (v) {
          if (v == null) return;
          _rebuild(() {
            _themeProfile = _themeProfile.copyWith(codeFontFamily: v);
            _profileTouched = true;
          });
        },
      ),
    ];
  }

  /// Het logo op een *dia*. Het documentlogo staat los (het mag afwijken) en
  /// wordt in het documentvlak van de stijlbouwer gezet.
  List<Widget> _slideLogoChildren() {
    final l10n = context.l10n;
    return [
      // Een logo wordt als pad in het themaprofiel bewaard, en zo'n pad bestaat
      // in de browser niet: de bestandskiezer geeft daar een blob:-URL terug
      // die na herladen nergens meer heen wijst. Dus verbergen we de hele
      // logo-instelling op web, net als de andere kiezers (zie
      // settings_dialog_storage.dart) — liever geen knop dan een knop die niet
      // doet wat hij belooft. Footer en slotdia blijven wél staan; die hebben
      // geen bestandssysteem nodig.
      if (supportsLocalProjectFolders) ...[
        _themeColorAnchor(
          'logoPath',
          Row(
            children: [
              Container(
                key: const Key('style-logo-preview'),
                width: 64,
                height: 52,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppTheme.slate100,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: AppTheme.slate300),
                ),
                child: ThemeProfileLogo(
                  profile: _themeProfile,
                  width: 54,
                  height: 42,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _pathBox(
                  _themeProfile.logoPath ?? l10n.d('Geen logo ingesteld'),
                  muted: _themeProfile.logoPath == null,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _pickLogo,
                icon: const Icon(Icons.image_outlined, size: 16),
                label: Text(l10n.d('Kiezen')),
              ),
              if (_themeProfile.logoPath != null)
                IconButton(
                  onPressed: () => _rebuild(() {
                    _themeProfile = _themeProfile.copyWith(clearLogo: true);
                    _profileTouched = true;
                  }),
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: l10n.d('Verwijder logo'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _themeProfile.logoPosition,
          decoration: InputDecoration(
            labelText: l10n.d('Logo positie'),
            isDense: true,
          ),
          items: [
            DropdownMenuItem(
              value: 'top-left',
              child: Text(l10n.d('Linksboven')),
            ),
            DropdownMenuItem(
              value: 'top-right',
              child: Text(l10n.d('Rechtsboven')),
            ),
            DropdownMenuItem(
              value: 'bottom-left',
              child: Text(l10n.d('Linksonder')),
            ),
            DropdownMenuItem(
              value: 'bottom-right',
              child: Text(l10n.d('Rechtsonder')),
            ),
          ],
          onChanged: (v) {
            if (v != null) {
              _rebuild(() {
                _themeProfile = _themeProfile.copyWith(logoPosition: v);
                _profileTouched = true;
              });
            }
          },
        ),
        const SizedBox(height: 14),
        // Donkere logo-variant: alleen zinnig met een lichte logo ingesteld.
        // Gebundelde merken kiezen automatisch; dit veld is voor een eigen logo.
        if (_themeProfile.logoPath != null) ...[
          _themeColorAnchor(
            'logoDarkPath',
            Row(
              children: [
                Container(
                  key: const Key('style-logo-dark-preview'),
                  width: 64,
                  height: 52,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: AppTheme.slate700),
                  ),
                  child: ThemeProfileLogo(
                    profile: _themeProfile,
                    logoPath: _themeProfile.logoDarkPath,
                    width: 54,
                    height: 42,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _pathBox(
                    _themeProfile.logoDarkPath ??
                        l10n.d('Geen donker logo ingesteld'),
                    muted: _themeProfile.logoDarkPath == null,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _pickLogoDark,
                  icon: const Icon(Icons.nights_stay_outlined, size: 16),
                  label: Text(l10n.d('Kiezen')),
                ),
                if (_themeProfile.logoDarkPath != null)
                  IconButton(
                    onPressed: () => _rebuild(() {
                      _themeProfile = _themeProfile.copyWith(
                        clearLogoDark: true,
                      );
                      _profileTouched = true;
                    }),
                    icon: const Icon(Icons.clear, size: 18),
                    tooltip: l10n.d('Verwijder donker logo'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        SizedBox(
          width: 160,
          child: TextField(
            controller: _logoSize,
            decoration: InputDecoration(
              labelText: context.l10n.d('Logo px'),
              isDense: true,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => _rebuild(() => _profileTouched = true),
          ),
        ),
      ],
    ];
  }

  List<Widget> _footerSettings() {
    final l10n = context.l10n;
    return [
      TextField(
        controller: _footerText,
        decoration: InputDecoration(
          labelText: l10n.d('Footertekst'),
          hintText: l10n.d('bijv. Vertrouwelijk · {title} · {date}'),
          isDense: true,
        ),
        onChanged: (_) => _rebuild(() => _profileTouched = true),
      ),
      const SizedBox(height: 6),
      Text(
        l10n.d(
          'Tokens: {page}, {total}, {date}, {title}. Footer verschijnt op alle slides behalve titel- en sectieslides, tenzij je hem per slide uitzet.',
        ),
        style: TextStyle(fontSize: 11, color: AppTheme.slate400),
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
        initialValue: _themeProfile.footerPosition,
        decoration: InputDecoration(
          labelText: l10n.d('Footerpositie'),
          isDense: true,
        ),
        items: [
          DropdownMenuItem(value: 'left', child: Text(l10n.d('Links'))),
          DropdownMenuItem(value: 'center', child: Text(l10n.d('Midden'))),
          DropdownMenuItem(value: 'right', child: Text(l10n.d('Rechts'))),
        ],
        onChanged: (v) {
          if (v != null) {
            _rebuild(() {
              _themeProfile = _themeProfile.copyWith(footerPosition: v);
              _profileTouched = true;
            });
          }
        },
      ),
      const SizedBox(height: 6),
      CheckboxListTile(
        value: _themeProfile.footerShowPageNumbers,
        onChanged: (v) => _rebuild(() {
          _themeProfile = _themeProfile.copyWith(
            footerShowPageNumbers: v ?? false,
          );
          _profileTouched = true;
        }),
        title: Text(
          l10n.d('Paginanummers tonen (rechtsonder)'),
          style: const TextStyle(fontSize: 13),
        ),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
      ),
    ];
  }

  List<Widget> _closingSlideSettings() {
    final l10n = context.l10n;
    return [
      SwitchListTile(
        value: _themeProfile.closingSlideEnabled,
        onChanged: (v) => _rebuild(() {
          _themeProfile = _themeProfile.copyWith(
            closingSlideEnabled: v,
            closingSlideMarkdown: _closingSlideMarkdown.text,
          );
          _profileTouched = true;
        }),
        title: Text(
          l10n.d('Standaard laatste slide gebruiken'),
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          l10n.d('Wordt automatisch toegevoegd bij presenteren en exporteren.'),
          style: TextStyle(fontSize: 11, color: AppTheme.slate500),
        ),
        contentPadding: EdgeInsets.zero,
        dense: true,
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _closingSlideMarkdown,
        enabled: _themeProfile.closingSlideEnabled,
        minLines: 4,
        maxLines: 8,
        decoration: InputDecoration(
          labelText: l10n.d('Markdown voor laatste slide'),
          hintText: l10n.d('# Bedankt\n\nVragen?'),
          alignLabelWithHint: true,
          isDense: true,
        ),
        onChanged: (value) {
          _themeProfile = _themeProfile.copyWith(closingSlideMarkdown: value);
          _profileTouched = true;
        },
      ),
    ];
  }

  /// Every contrast problem the quality panel would raise for the current
  /// profile, keyed by the colour field it belongs to (an error outranks a
  /// warning on the same field). Runs the real [SlideQualityAnalyzer] — with the
  /// user's own [AppSettings.contrastMinRatio] threshold — over two probe slides
  /// (a checklist and a section slide) so the deck-conditional checklist and
  /// section checks fire too. Driving the editor from the analyzer keeps its
  /// inline warnings exactly in step with the deck-level quality report: any
  /// pairing the panel flags in a presentation is flagged here in the style.
  Map<String, SlideQualityIssue> _themeContrastByField() {
    final analyzer = SlideQualityAnalyzer(
      minContrastRatio: ref.read(settingsProvider).contrastMinRatio,
    );
    final result = analyzer.analyzeSlides(
      slides: [
        const Slide(id: '_probe_section', type: SlideType.section, title: 'x'),
        const Slide(
          id: '_probe_checklist',
          type: SlideType.bullets,
          listStyle: ListStyle.checklist,
          bullets: ['x'],
        ),
      ],
      theme: _themeProfile,
      font: _themeProfile.fontFamily,
    );
    final byField = <String, SlideQualityIssue>{};
    for (final issue in result.issues) {
      if (issue.category != SlideQualityCategory.contrast) continue;
      // The section-slide title check carries no field; fold it into the title
      // colour it actually tests (titleTextColor vs sectionBackgroundColor).
      final field =
          issue.field ??
          (issue.kind == SlideQualityIssueKind.slideContrast
              ? 'titleTextColor'
              : null);
      if (field == null) continue;
      // An error outranks a warning already recorded for the same field.
      final existing = byField[field];
      if (existing != null &&
          existing.severity == MarkdownValidationSeverity.error) {
        continue;
      }
      byField[field] = issue;
    }
    return byField;
  }

  /// Wraps a colour picker and appends a readability warning underneath when the
  /// quality analyser flags [field] on the current profile. The warning updates
  /// live because the whole colours tab rebuilds on every edit.
  Widget _colorWithContrastWarning(
    Widget colorSetting,
    String field,
    Map<String, SlideQualityIssue> contrast,
  ) {
    final issue = contrast[field];
    if (issue == null) return colorSetting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [colorSetting, _contrastWarning(issue)],
    );
  }

  /// The inline warning shown under a colour the quality panel would flag — e.g.
  /// white title text on a white title background, where the title becomes
  /// invisible. Coloured by severity so it mirrors the panel (amber for a
  /// warning, red for a hard contrast error), shows the actual ratio inline, and
  /// carries the panel's full message (label, ratio and threshold) as a tooltip.
  Widget _contrastWarning(SlideQualityIssue issue) {
    final color = issue.severity == MarkdownValidationSeverity.error
        ? AppTheme.dangerFg
        : AppTheme.warningFg;
    final ratio = issue.args['ratio'];
    return Tooltip(
      message: formatSlideQualityIssue(context.l10n, issue),
      child: Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, size: 15, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                context.l10n.d(
                  'Te weinig contrast met de achtergrond — mogelijk onleesbaar.',
                ),
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (ratio != null) ...[
              const SizedBox(width: 6),
              Text(
                '$ratio:1',
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _colorSetting(
    String label,
    String value,
    ValueChanged<String> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label  $value',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.slate700,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final color in _SettingsDialogState._colorPresets)
              _colorSwatchButton(
                context,
                color,
                selected: value.toUpperCase() == color,
                onTap: () => _rebuild(() {
                  onChanged(color);
                  _profileTouched = true;
                }),
              ),
            // Show the current value as a selected swatch when it isn't one of
            // the presets (e.g. a hand-entered CRT green).
            if (!_SettingsDialogState._colorPresets.contains(
              value.toUpperCase(),
            ))
              _colorSwatchButton(
                context,
                value,
                selected: true,
                onTap: () => _editCustomColor(value, onChanged),
              ),
            _customColorButton(value, onChanged),
          ],
        ),
      ],
    );
  }

  Widget _customColorButton(String value, ValueChanged<String> onChanged) {
    return Tooltip(
      message: context.l10n.d('Eigen kleur (hex)'),
      child: InkWell(
        onTap: () => _editCustomColor(value, onChanged),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.slate300),
          ),
          child: Icon(Icons.tune, size: 18, color: AppTheme.slate500),
        ),
      ),
    );
  }

  Future<void> _editCustomColor(
    String initial,
    ValueChanged<String> onChanged,
  ) async {
    final picked = await _pickHexColor(initial);
    if (picked == null || !mounted) return;
    _rebuild(() {
      onChanged(picked);
      _profileTouched = true;
    });
  }

  Future<String?> _pickHexColor(String initial) =>
      HexColorDialog.show(context, initial);
}

/// Eén kleurvlakje in een kleurkiezer.
///
/// Top-level en niet in `_SettingsDialogState`: het leest geen enkel veld van
/// dat scherm — alleen de kleur, of hij gekozen is en wat er bij een tik moet
/// gebeuren. In de klasse duwde het haar tegen het plafond van de
/// omvangs-ratchet aan, zonder er iets voor terug te geven.
Widget _colorSwatchButton(
  BuildContext context,
  String color, {
  required bool selected,
  required VoidCallback onTap,
}) {
  final parsed = AppTheme.parseHexColor(color);
  final checkColor = parsed.computeLuminance() > 0.55
      ? AppTheme.ink
      : Colors.white;
  return Tooltip(
    message: selected ? '${context.l10n.d('Geselecteerd')}: $color' : color,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 34,
        height: 34,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppTheme.accentFg : AppTheme.slate300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                color: parsed,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: AppTheme.inkOverlay,
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(
                Icons.check,
                size: 16,
                color: checkColor,
                shadows: [
                  Shadow(
                    color: checkColor == Colors.white
                        ? Colors.black54
                        : Colors.white70,
                    blurRadius: 2,
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}
