import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/cwe_entry.dart';
import '../../services/cwe_catalog.dart';
import '../../theme/app_theme.dart';

/// A searchable picker over the offline CWE catalog ([CweCatalog],
/// PENTEST_MIAUW §10.6). Returns the chosen [CweEntry] (or null on cancel); the
/// finding editor sets its CWE field from it and fills empty description /
/// recommendation sections with the entry's deterministic snippet.
class CwePicker extends StatefulWidget {
  const CwePicker({super.key});

  static Future<CweEntry?> show(BuildContext context) =>
      showDialog<CweEntry>(context: context, builder: (_) => const CwePicker());

  @override
  State<CwePicker> createState() => _CwePickerState();
}

class _CwePickerState extends State<CwePicker> {
  final _search = TextEditingController();
  final _catalog = CweCatalog.instance;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    // Serve the curated floor immediately; grow to the full offline list once
    // the bundled asset is parsed (a one-off, a few ms).
    _catalog.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final matches = _catalog.search(_search.text);
    return AlertDialog(
      title: Text(l10n.d('CWE kiezen')),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: l10n.d('Zoek op naam of CWE-nummer'),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: matches.isEmpty
                  ? Center(child: Text(l10n.d('Geen CWE gevonden')))
                  : ListView.separated(
                      itemCount: matches.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) => _tile(context, matches[i]),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Annuleren')),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, CweEntry entry) {
    return ListTile(
      title: Text('${context.l10n.d('CWE')}-${entry.id} — ${entry.name}'),
      subtitle: Text(
        entry.description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(Icons.chevron_right, color: AppTheme.slate400),
      onTap: () => Navigator.of(context).pop(entry),
    );
  }
}
