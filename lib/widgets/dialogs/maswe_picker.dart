import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/maswe_weakness.dart';
import '../../services/maswe_catalog.dart';
import '../../theme/app_theme.dart';

/// Een doorzoekbare kiezer over de gebundelde MASWE-lijst, tegenhanger van
/// [CwePicker] voor mobiel. Geeft de gekozen [MasweWeakness] terug, of null.
///
/// Toont uitgeschreven zwakheden bovenaan en markeert de rest. Dat is geen
/// opsmuk: drie kwart van MASWE is bij de bron nog een concept, en zonder dat
/// onderscheid zou een tester een zwakheid kiezen en op een lege pagina
/// belanden zonder te begrijpen waarom.
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

  /// Zoekt op id, titel en categorie. Uitgeschreven zwakheden eerst, want die
  /// hebben een pagina waar de lezer van het rapport iets aan heeft.
  List<MasweWeakness> get _matches {
    final q = _search.text.trim().toLowerCase();
    final all = MasweCatalog.instance.weaknesses.where((w) {
      if (q.isEmpty) return true;
      return w.id.toLowerCase().contains(q) ||
          w.title.toLowerCase().contains(q) ||
          w.category.toLowerCase().contains(q);
    }).toList();
    all.sort((a, b) {
      if (a.isPlaceholder != b.isPlaceholder) return a.isPlaceholder ? 1 : -1;
      return a.id.compareTo(b.id);
    });
    return all;
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
                      itemBuilder: (context, i) => _tile(l10n, matches[i]),
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

  Widget _tile(AppLocalizations l10n, MasweWeakness w) {
    final subtitle = [
      w.category,
      if (w.cweIds.isNotEmpty) 'CWE-${w.cweIds.join(', CWE-')}',
      if (w.isPlaceholder) l10n.d('uitleg nog niet geschreven'),
    ].join(' · ');

    return ListTile(
      title: Text('${w.id} — ${w.title}'),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          color: w.isPlaceholder ? AppTheme.amber600 : AppTheme.slate400,
        ),
      ),
      trailing: Icon(Icons.chevron_right, color: AppTheme.slate400),
      onTap: () => Navigator.of(context).pop(w),
    );
  }
}
