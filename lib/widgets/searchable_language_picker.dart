import 'package:material_ui/material_ui.dart';
import '../l10n/app_localizations.dart';
import 'language_flag.dart';

/// A compact language selector that opens a searchable dialog.
///
/// Shows the current language as an outlined field (flag + name). Tapping opens
/// a dialog with a search box that filters by language code (e.g. "nl") and
/// display name (e.g. "Nederlands"), with diacritics folded via
/// [AppLocalizations.sortKey]. Selecting a language immediately calls
/// [onLanguageChanged].
class SearchableLanguagePicker extends StatefulWidget {
  final String languageCode;
  final ValueChanged<String> onLanguageChanged;
  final double? width;

  /// Label above the field; omit for a label-less compact box.
  final String? labelText;

  const SearchableLanguagePicker({
    super.key,
    required this.languageCode,
    required this.onLanguageChanged,
    this.width,
    this.labelText,
  });

  @override
  State<SearchableLanguagePicker> createState() =>
      _SearchableLanguagePickerState();
}

class _SearchableLanguagePickerState extends State<SearchableLanguagePicker> {
  void _openSearch() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _LanguageSearchDialog(
        currentCode: widget.languageCode,
        onSelected: (code) {
          Navigator.pop(dialogContext);
          widget.onLanguageChanged(code);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name =
        AppLocalizations.languageNames[widget.languageCode] ??
        widget.languageCode;
    return SizedBox(
      width: widget.width ?? 200,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.labelText,
          isDense: true,
          prefixIcon: const Icon(Icons.language, size: 16),
          border: const OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 10,
            vertical: widget.labelText != null ? 2 : 10,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _openSearch,
            child: Row(
              children: [
                languageFlag(widget.languageCode, size: 15),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.search,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageSearchDialog extends StatefulWidget {
  final String currentCode;
  final ValueChanged<String> onSelected;

  const _LanguageSearchDialog({
    required this.currentCode,
    required this.onSelected,
  });

  @override
  State<_LanguageSearchDialog> createState() => _LanguageSearchDialogState();
}

class _LanguageSearchDialogState extends State<_LanguageSearchDialog> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<MapEntry<String, String>> get _filtered {
    final q = _query.trim().toLowerCase();
    final options = AppLocalizations.languageOptions;
    if (q.isEmpty) return options;
    return options.where((entry) {
      return entry.key.toLowerCase().contains(q) ||
          entry.value.toLowerCase().contains(q) ||
          AppLocalizations.sortKey(entry.value).contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final items = _filtered;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: l10n.d('Zoek op taal of code'),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          tooltip: l10n.d('Zoekveld wissen'),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Flexible(
              child: items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.d('Geen talen gevonden'),
                        style: TextStyle(color: theme.hintColor),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final entry = items[i];
                        final selected = entry.key == widget.currentCode;
                        return ListTile(
                          dense: true,
                          selected: selected,
                          leading: SizedBox(
                            width: 24,
                            child: Center(
                              child: languageFlag(entry.key, size: 17),
                            ),
                          ),
                          title: Text(
                            entry.value,
                            style: const TextStyle(fontSize: 13),
                          ),
                          trailing: Text(
                            entry.key,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          onTap: () => widget.onSelected(entry.key),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
