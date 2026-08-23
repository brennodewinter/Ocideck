import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/maswe_weakness.dart';
import '../../services/maswe_catalog.dart';
import '../../theme/app_theme.dart';

/// Een doorzoekbare kiezer over de gebundelde MASWE-lijst, tegenhanger van
/// [CwePicker] voor mobiel. Geeft de gekozen [MasweWeakness] terug, of null.
///
/// Sinds de herbouw van MASWE (medio 2026) zijn alle 78 zwakheden
/// uitgeschreven; er is geen concept-onderscheid meer te tonen. De lijst staat
/// simpelweg op id-volgorde.
class MaswePicker extends StatefulWidget {
  const MaswePicker({super.key});

  static Future<MasweWeakness?> show(BuildContext context) =>
      showDialog<MasweWeakness>(
        context: context,
        builder: (_) => const MaswePicker(),
      );

  @override
  State<MaswePicker> createState() => _MaswePickerState();
}

class _MaswePickerState extends State<MaswePicker> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Zoekt op id, titel en categorie; de uitkomst blijft op id-volgorde.
  List<MasweWeakness> get _matches {
    final q = _search.text.trim().toLowerCase();
    return MasweCatalog.instance.weaknesses.where((w) {
      if (q.isEmpty) return true;
      return w.id.toLowerCase().contains(q) ||
          w.title.toLowerCase().contains(q) ||
          w.category.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final matches = _matches;
    return AlertDialog(
      title: Text(l10n.d('MASWE-zwakheid kiezen')),
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
                hintText: l10n.d('Zoek op naam, id of categorie'),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: matches.isEmpty
                  ? Center(child: Text(l10n.d('Geen zwakheid gevonden')))
                  : ListView.separated(
                      itemCount: matches.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) => _tile(matches[i]),
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

  Widget _tile(MasweWeakness w) {
    final subtitle = [
      w.category,
      if (w.cweIds.isNotEmpty) 'CWE-${w.cweIds.join(', CWE-')}',
    ].join(' · ');

    return ListTile(
      title: Text('${w.id} — ${w.title}'),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11.5, color: AppTheme.slate400),
      ),
      trailing: Icon(Icons.chevron_right, color: AppTheme.slate400),
      onTap: () => Navigator.of(context).pop(w),
    );
  }
}
