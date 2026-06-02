import 'package:flutter/material.dart';

/// Telt hoe vaak [query] voorkomt in de hele presentatie.
typedef MatchCounter = int Function(String query, bool caseSensitive);

/// Vervangt alle voorkomens en geeft het aantal vervangingen terug.
typedef ReplaceRunner =
    int Function(String query, String replacement, bool caseSensitive);

/// Zoek-en-vervang over alle slides van de huidige presentatie.
class FindReplaceDialog extends StatefulWidget {
  final MatchCounter countMatches;
  final ReplaceRunner replaceAll;

  const FindReplaceDialog({
    super.key,
    required this.countMatches,
    required this.replaceAll,
  });

  static Future<void> show(
    BuildContext context, {
    required MatchCounter countMatches,
    required ReplaceRunner replaceAll,
  }) {
    return showDialog(
      context: context,
      builder: (_) =>
          FindReplaceDialog(countMatches: countMatches, replaceAll: replaceAll),
    );
  }

  @override
  State<FindReplaceDialog> createState() => _FindReplaceDialogState();
}

class _FindReplaceDialogState extends State<FindReplaceDialog> {
  final _find = TextEditingController();
  final _replace = TextEditingController();
  final _findFocus = FocusNode();
  bool _caseSensitive = false;
  int _matches = 0;
  int? _replaced; // aantal van de laatste vervang-actie (feedback)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _findFocus.requestFocus(),
    );
  }

  @override
  void dispose() {
    _find.dispose();
    _replace.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  void _recount() {
    setState(() {
      _matches = widget.countMatches(_find.text, _caseSensitive);
      _replaced = null;
    });
  }

  void _runReplace() {
    final query = _find.text;
    if (query.isEmpty) return;
    final n = widget.replaceAll(query, _replace.text, _caseSensitive);
    setState(() {
      _replaced = n;
      // Hertel: meestal 0, tenzij de vervangtekst de zoekterm bevat.
      _matches = widget.countMatches(query, _caseSensitive);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _find.text.isNotEmpty;
    return AlertDialog(
      title: const Text('Zoeken en vervangen'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _find,
              focusNode: _findFocus,
              onChanged: (_) => _recount(),
              decoration: const InputDecoration(
                labelText: 'Zoeken naar',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _replace,
              onChanged: (_) => setState(() => _replaced = null),
              decoration: const InputDecoration(
                labelText: 'Vervangen door',
                prefixIcon: Icon(Icons.edit_outlined, size: 18),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: _caseSensitive,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) {
                    _caseSensitive = v ?? false;
                    _recount();
                  },
                ),
                const Text(
                  'Hoofdlettergevoelig',
                  style: TextStyle(fontSize: 13),
                ),
                const Spacer(),
                _statusText(hasQuery),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Sluiten'),
        ),
        FilledButton.icon(
          onPressed: (hasQuery && _matches > 0) ? _runReplace : null,
          icon: const Icon(Icons.find_replace, size: 16),
          label: const Text('Vervang alles'),
        ),
      ],
    );
  }

  Widget _statusText(bool hasQuery) {
    if (_replaced != null) {
      return Text(
        _replaced == 0
            ? 'Niets vervangen'
            : _replaced == 1
            ? '1 vervangen'
            : '$_replaced vervangen',
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF15803D),
          fontWeight: FontWeight.w600,
        ),
      );
    }
    if (!hasQuery) return const SizedBox.shrink();
    return Text(
      _matches == 0
          ? 'Geen resultaten'
          : _matches == 1
          ? '1 resultaat'
          : '$_matches resultaten',
      style: TextStyle(
        fontSize: 12,
        color: _matches == 0
            ? const Color(0xFF94A3B8)
            : const Color(0xFF2563EB),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
