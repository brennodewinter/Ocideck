part of 'markdown_deck_editor.dart';

// De losse hulp-widgets en dataklassen onder de markdown-editor — de status-
// en validatiebanden, de scope-schakelaar, de outline-knop en de toepas-keuze —
// plus de opmaakbalk. Een part omdat ze op de private editor-state leunen; zie
// het hoofdbestand.

Widget _formattingBar(_MarkdownDeckEditorState state) {
  final theme = MarkdownEditorTheme.editorPanel(
    text: AppTheme.ink,
    link: AppTheme.accentFg,
    accent: AppTheme.accentFg,
    codeBackground: AppTheme.slate100,
    border: AppTheme.slate200,
    fontSize: 13,
  );
  return ColoredBox(
    color: AppTheme.slate50,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: state._undoController.value.canUndo
                ? state._undoController.undo
                : null,
            icon: const Icon(Icons.undo, size: 18),
            tooltip: state.context.l10n.d('Ongedaan maken'),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: state._undoController.value.canRedo
                ? state._undoController.redo
                : null,
            icon: const Icon(Icons.redo, size: 18),
            tooltip: state.context.l10n.d('Opnieuw'),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: MarkdownEditorToolbar(
              controller: state._ctrl,
              focusNode: state._editorFocusNode,
              theme: theme,
              compact: false,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MarkdownSourceStatusBar extends StatelessWidget {
  final String text;
  final TextSelection selection;
  final int? slideNumber;
  final int writingSuggestionCount;
  final VoidCallback? onWritingSuggestions;

  const _MarkdownSourceStatusBar({
    required this.text,
    required this.selection,
    required this.slideNumber,
    required this.writingSuggestionCount,
    required this.onWritingSuggestions,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final offset = selection.isValid
        ? selection.extentOffset.clamp(0, text.length)
        : 0;
    final before = text.substring(0, offset);
    final line = '\n'.allMatches(before).length + 1;
    final lastBreak = before.lastIndexOf('\n');
    final column = offset - lastBreak;
    final plain = text
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ')
        .replaceAll(RegExp(r'!?\[[^\]]*\]\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'[`*_#>|~-]+'), ' ');
    final words = plain.trim().isEmpty
        ? 0
        : plain.trim().split(RegExp(r'\s+')).length;
    final speakingSeconds = (words * 60 / 130).round();
    final duration = speakingSeconds < 60
        ? '${speakingSeconds}s'
        : '${speakingSeconds ~/ 60}:${(speakingSeconds % 60).toString().padLeft(2, '0')}';
    final style = TextStyle(fontSize: 10.5, color: AppTheme.slate500);
    return Semantics(
      label:
          '${slideNumber == null ? '' : '${l10n.d('Dia')} $slideNumber, '}'
          '${l10n.d('Regel')} $line, ${l10n.d('kolom')} $column, '
          '$words ${l10n.d('woorden')}',
      child: Container(
        height: 24,
        color: AppTheme.slate100,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              if (slideNumber != null) ...[
                Text('${l10n.d('Dia')} $slideNumber', style: style),
                const SizedBox(width: 10),
              ],
              Text(
                '${l10n.d('Regel')} $line · ${l10n.d('kolom')} $column',
                style: style,
              ),
              const Spacer(),
              Text('$words ${l10n.d('woorden')}', style: style),
              if (constraints.maxWidth >= 420) ...[
                const SizedBox(width: 12),
                Text('${text.length} ${l10n.d('tekens')}', style: style),
                const SizedBox(width: 12),
                Icon(
                  Icons.record_voice_over_outlined,
                  size: 12,
                  color: AppTheme.slate500,
                ),
                const SizedBox(width: 3),
                Text('± $duration', style: style),
              ],
              if (constraints.maxWidth >= 560 &&
                  writingSuggestionCount > 0) ...[
                const SizedBox(width: 12),
                InkWell(
                  onTap: onWritingSuggestions,
                  child: Row(
                    children: [
                      Icon(
                        Icons.tips_and_updates_outlined,
                        size: 12,
                        color: AppTheme.warningFg,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$writingSuggestionCount ${l10n.d('schrijftips')}',
                        style: style.copyWith(color: AppTheme.warningFg),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Geanimeerde segmented-toggle waarmee de markdown-modus wisselt tussen de
/// hele presentatie en alleen de actieve slide. Een wit "pilletje" schuift
/// vloeiend onder het gekozen segment.
class _MarkdownScopeToggle extends StatelessWidget {
  final MarkdownScope scope;
  final int slideNumber;
  final int slideCount;
  final ValueChanged<MarkdownScope> onChanged;

  const _MarkdownScopeToggle({
    required this.scope,
    required this.slideNumber,
    required this.slideCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isSlide = scope == MarkdownScope.slide;
    final fg = AppTheme.warningFg;
    return Container(
      height: 30,
      constraints: const BoxConstraints(maxWidth: 360),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.all(2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // Het schuivende, gemarkeerde segment.
              AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: isSlide
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  _segment(
                    icon: Icons.view_carousel_outlined,
                    label: l10n.d('Volledige presentatie'),
                    active: !isSlide,
                    onTap: () => onChanged(MarkdownScope.deck),
                  ),
                  _segment(
                    icon: Icons.crop_square_outlined,
                    label: '${l10n.d('Deze slide')} · $slideNumber/$slideCount',
                    active: isSlide,
                    onTap: () => onChanged(MarkdownScope.slide),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _segment({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final fg = AppTheme.warningFg;
    final color = active ? fg : fg.withValues(alpha: 0.6);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showIcon = constraints.maxWidth >= 48;
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: constraints.maxWidth >= 80 ? 8 : 2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (showIcon) ...[
                    Icon(icon, size: 14, color: color),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DocumentStatus extends StatelessWidget {
  final bool dirty;
  final bool validationPending;
  final MarkdownValidationResult? validation;
  final VoidCallback? onPressed;

  const _DocumentStatus({
    required this.dirty,
    required this.validationPending,
    required this.validation,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (icon, label, color) = validation?.hasIssues == true
        ? (
            Icons.warning_amber_outlined,
            l10n.d('Problemen gevonden'),
            AppTheme.dangerFg,
          )
        : dirty
        ? (Icons.edit_outlined, l10n.d('Niet toegepast'), AppTheme.warningFg)
        : validationPending
        ? (Icons.sync, l10n.d('Controleren…'), AppTheme.slate500)
        : (Icons.check, l10n.d('Actueel'), AppTheme.successFg);
    return Semantics(
      liveRegion: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(icon, size: 15, color: color),
          ),
        ),
      ),
    );
  }
}

class _MarkdownOutlineButton extends StatelessWidget {
  final List<MarkdownOutlineEntry> entries;
  final ValueChanged<int> onSelected;

  const _MarkdownOutlineButton({
    required this.entries,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopupMenuButton<int>(
      tooltip: l10n.d('Documentoverzicht'),
      enabled: entries.isNotEmpty,
      padding: EdgeInsets.zero,
      iconSize: 14,
      icon: const Icon(Icons.account_tree_outlined),
      color: AppTheme.paper,
      constraints: const BoxConstraints(maxHeight: 420, minWidth: 260),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final entry in entries)
          PopupMenuItem<int>(
            value: entry.line,
            height: 36,
            child: Row(
              children: [
                SizedBox(
                  width: 42,
                  child: Text(
                    '${l10n.d('Dia')} ${entry.slideNumber}',
                    style: TextStyle(fontSize: 10, color: AppTheme.slate500),
                  ),
                ),
                SizedBox(width: (entry.level - 1) * 10.0),
                Expanded(
                  child: Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: entry.level == 1
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

enum _ApplyChoice { edit, cancel, applyAnyway }

class _ApplyChoiceResult {
  final _ApplyChoice choice;
  final int? focusLine;

  const _ApplyChoiceResult(this.choice, [this.focusLine]);
}

/// De uitkomst van de syntaxcontrole, als een balk die blijft staan.
///
/// [result] is bewust het *vorige* oordeel zolang [pending] waar is. De balk
/// leegmaken tijdens het typen haalde hem uit de [Column], waardoor de editor
/// eronder 28 px omhoog sprong en na 350 ms weer terug — bij elke aanslag
/// (#1555). Door het oordeel te laten staan en alleen icoon en tekst te
/// wisselen, verandert de hoogte alleen als het oordeel zelf verandert.
class _ValidationSummaryBar extends StatelessWidget {
  final MarkdownValidationResult result;

  /// Er loopt een nieuwe controle; [result] is het vorige oordeel.
  final bool pending;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<int> onJumpToLine;
  final VoidCallback? Function(MarkdownValidationIssue) quickFixFor;

  const _ValidationSummaryBar({
    required this.result,
    required this.pending,
    required this.expanded,
    required this.onToggle,
    required this.onJumpToLine,
    required this.quickFixFor,
  });

  Future<void> _copyIssues(BuildContext context) async {
    final l10n = context.l10n;
    final buf = StringBuffer();
    for (final issue in result.issues) {
      buf.writeln('Regel ${issue.line}: ${issue.message}');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.d('Syntaxproblemen gekopieerd naar klembord.')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = result.isValid ? AppTheme.warningBg : AppTheme.dangerBg;
    final iconColor = result.isValid ? AppTheme.warningFg : AppTheme.dangerFg;
    final summary = pending
        ? l10n.d('Controleren…')
        : result.hasIssues
        ? '${result.errorCount} ${l10n.d('fout(en),')} '
              '${result.warningCount} ${l10n.d('waarschuwing(en)')}'
        : l10n.d('Geen syntaxproblemen gevonden');

    return Material(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: result.hasIssues ? onToggle : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    pending
                        ? Icons.sync
                        : result.hasIssues
                        ? Icons.warning_amber_outlined
                        : Icons.check_circle_outline,
                    size: 14,
                    color: iconColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      summary,
                      style: TextStyle(fontSize: 11, color: iconColor),
                    ),
                  ),
                  if (result.hasIssues) ...[
                    IconButton(
                      icon: const Icon(Icons.copy_outlined),
                      iconSize: 14,
                      color: iconColor,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      tooltip: l10n.d('Kopieer syntaxproblemen'),
                      onPressed: () => _copyIssues(context),
                    ),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: iconColor,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (expanded && result.hasIssues)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                itemCount: result.issues.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final issue = result.issues[index];
                  return _IssueTile(
                    issue: issue,
                    onTap: () => onJumpToLine(issue.line),
                    onQuickFix: quickFixFor(issue),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _IssueTile extends StatelessWidget {
  final MarkdownValidationIssue issue;
  final VoidCallback onTap;
  final VoidCallback? onQuickFix;

  const _IssueTile({required this.issue, required this.onTap, this.onQuickFix});

  @override
  Widget build(BuildContext context) {
    final isError = issue.severity == MarkdownValidationSeverity.error;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.info_outline,
              size: 14,
              color: isError ? AppTheme.dangerFg : AppTheme.warningFg,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${context.l10n.d('Regel')} ${issue.line}: ${issue.message}',
                style: TextStyle(
                  fontSize: 11,
                  color: isError ? AppTheme.dangerFg : AppTheme.warningFg,
                ),
              ),
            ),
            if (onQuickFix != null)
              IconButton(
                onPressed: onQuickFix,
                tooltip: context.l10n.d('Snel herstellen'),
                icon: const Icon(Icons.auto_fix_high, size: 14),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 24),
                padding: EdgeInsets.zero,
              ),
          ],
        ),
      ),
    );
  }
}
