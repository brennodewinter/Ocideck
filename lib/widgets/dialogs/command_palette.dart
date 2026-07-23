import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// Eén doorzoekbare actie in het commandopalet (Ctrl/Cmd+K).
///
/// De handler ([onInvoke]) draait pas nadat het palet gesloten is, zodat een
/// commando dat zelf een dialoog opent niet meteen door de palet-barrier wordt
/// weggeklikt (zie [_CommandPaletteState._invoke]).
class PaletteCommand {
  /// Zichtbaar, gelokaliseerd label.
  final String label;
  final IconData icon;

  /// Taalneutrale sneltoets-hint rechts (bijv. 'Ctrl/Cmd+S'); null = geen.
  final String? shortcut;

  /// Extra zoektermen (taalneutraal, bijv. 'pdf', 'tlp') naast het [label].
  final List<String> keywords;

  /// Grijs en niet-uitvoerbaar wanneer false (bijv. export vóór opslaan).
  final bool enabled;

  final VoidCallback onInvoke;

  const PaletteCommand({
    required this.label,
    required this.icon,
    required this.onInvoke,
    this.shortcut,
    this.keywords = const [],
    this.enabled = true,
  });
}

/// Het commandopalet: een doorzoekbare overlay met alle acties. Typen filtert,
/// pijltjes navigeren, Enter voert uit, Escape sluit.
class CommandPalette extends StatefulWidget {
  final List<PaletteCommand> commands;

  const CommandPalette({super.key, required this.commands});

  static Future<void> show(
    BuildContext context,
    List<PaletteCommand> commands,
  ) {
    return showDialog<void>(
      context: context,
      builder: (_) => CommandPalette(commands: commands),
    );
  }

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  static const _rowExtent = 44.0;
  static const _maxListHeight = 360.0;

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();
  String _query = '';
  int _selected = 0;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Diakriet-ongevoelig filteren (via [AppLocalizations.sortKey], zodat é→e),
  /// gerangschikt op hoe vroeg de zoekterm in label/zoektermen voorkomt.
  List<PaletteCommand> get _filtered {
    final q = AppLocalizations.sortKey(_query.trim());
    if (q.isEmpty) return widget.commands;
    final scored = <({int score, PaletteCommand cmd})>[];
    for (final cmd in widget.commands) {
      final score = _matchScore(cmd, q);
      if (score >= 0) scored.add((score: score, cmd: cmd));
    }
    scored.sort((a, b) => a.score.compareTo(b.score));
    return [for (final s in scored) s.cmd];
  }

  int _matchScore(PaletteCommand cmd, String foldedQuery) {
    var best = -1;
    for (final hay in [cmd.label, ...cmd.keywords]) {
      final i = AppLocalizations.sortKey(hay).indexOf(foldedQuery);
      if (i >= 0 && (best < 0 || i < best)) best = i;
    }
    return best;
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
      _selected = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _move(int delta, int count) {
    if (count == 0) return;
    setState(() => _selected = (_selected + delta).clamp(0, count - 1));
    _ensureVisible(_selected);
  }

  void _ensureVisible(int index) {
    if (!_scroll.hasClients) return;
    final top = index * _rowExtent;
    final bottom = top + _rowExtent;
    final viewport = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (bottom > _scroll.offset + viewport) {
      _scroll.jumpTo(bottom - viewport);
    }
  }

  void _invokeSelected(List<PaletteCommand> filtered) {
    if (_selected < 0 || _selected >= filtered.length) return;
    _runCommand(filtered[_selected]);
  }

  void _runCommand(PaletteCommand cmd) {
    if (!cmd.enabled) return;
    Navigator.of(context).pop();
    // Ná het sluiten uitvoeren: opent het commando zelf een dialoog, dan mag de
    // palet-barrier die niet meteen wegklikken.
    WidgetsBinding.instance.addPostFrameCallback((_) => cmd.onInvoke());
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final filtered = _filtered;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _move(1, filtered.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _move(-1, filtered.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _invokeSelected(filtered);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        Navigator.of(context).maybePop();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filtered = _filtered;
    if (_selected >= filtered.length) _selected = filtered.length - 1;
    if (_selected < 0) _selected = 0;

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 84, left: 16, right: 16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _searchField(l10n),
              const Divider(height: 1),
              Flexible(
                child: filtered.isEmpty ? _emptyState(l10n) : _list(filtered),
              ),
              const Divider(height: 1),
              _footer(l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchField(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: AppTheme.slate400),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              autofocus: true,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: l10n.d('Typ een commando…'),
              ),
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(List<PaletteCommand> filtered) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _maxListHeight),
      child: ListView.builder(
        controller: _scroll,
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemExtent: _rowExtent,
        itemCount: filtered.length,
        itemBuilder: (_, i) => _row(filtered[i], i == _selected),
      ),
    );
  }

  Widget _row(PaletteCommand cmd, bool selected) {
    final Color fg = !cmd.enabled
        ? AppTheme.slate400
        : selected
        ? AppTheme.tealFg
        : AppTheme.slate700;
    return InkWell(
      onTap: cmd.enabled ? () => _runCommand(cmd) : null,
      child: Container(
        color: selected ? AppTheme.teal.withValues(alpha: 0.10) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(cmd.icon, size: 18, color: fg),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                cmd.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: fg,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (cmd.shortcut != null) ...[
              const SizedBox(width: 10),
              _shortcutHint(cmd.shortcut!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _shortcutHint(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.slate300),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: AppTheme.slate500),
      ),
    );
  }

  Widget _emptyState(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(
          l10n.d('Geen resultaten'),
          style: TextStyle(fontSize: 13, color: AppTheme.slate500),
        ),
      ),
    );
  }

  Widget _footer(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: DefaultTextStyle(
        style: TextStyle(fontSize: 11, color: AppTheme.slate500),
        child: Row(
          children: [
            _footerHint('↑↓', l10n.d('Kiezen')),
            const SizedBox(width: 16),
            _footerHint('↵', l10n.d('Uitvoeren')),
            const SizedBox(width: 16),
            _footerHint(l10n.d('esc'), l10n.d('Sluiten')),
          ],
        ),
      ),
    );
  }

  Widget _footerHint(String key, String label) {
    return Row(
      children: [_shortcutHint(key), const SizedBox(width: 6), Text(label)],
    );
  }
}
