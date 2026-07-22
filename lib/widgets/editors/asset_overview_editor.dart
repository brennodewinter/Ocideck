import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/asset_overview_spec.dart';
import '../../models/slide.dart';
import '../../theme/app_theme.dart';
import '_editor_field.dart';

/// Editor for an `assets` slide: a title plus up to [assetOverviewMaxGroups]
/// kinds of exposed object, each with how many there are, how many need work,
/// how many are new and how many nobody owns. Emits the slide title and
/// `tableRows` via [AssetOverviewSpec]; storage stays a Markdown table.
///
/// The counts are typed in rather than counted by the app: OciDeck does not scan
/// anything. They come from whatever tool produced the report, which is also why
/// the table form matters — a generator can write it directly.
class AssetOverviewEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final bool nestedInScrollView;

  const AssetOverviewEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.nestedInScrollView = false,
  });

  @override
  State<AssetOverviewEditor> createState() => _AssetOverviewEditorState();
}

class _GroupControllers {
  _GroupControllers(AssetGroup group, VoidCallback onChanged)
    : name = TextEditingController(text: group.name)..addListener(onChanged),
      total = TextEditingController(text: _count(group.total))
        ..addListener(onChanged),
      atRisk = TextEditingController(text: _count(group.atRisk))
        ..addListener(onChanged),
      newlyFound = TextEditingController(text: _count(group.newlyFound))
        ..addListener(onChanged),
      unowned = TextEditingController(text: _count(group.unowned))
        ..addListener(onChanged);

  /// A zero shows as an empty field: a fresh row should invite a figure, not
  /// present a nought the author has to select and overwrite.
  static String _count(int value) => value == 0 ? '' : '$value';

  final TextEditingController name;
  final TextEditingController total;
  final TextEditingController atRisk;
  final TextEditingController newlyFound;
  final TextEditingController unowned;

  AssetGroup toGroup() => AssetGroup(
    name: name.text.trim(),
    total: parseAssetCount(total.text) ?? 0,
    atRisk: parseAssetCount(atRisk.text) ?? 0,
    newlyFound: parseAssetCount(newlyFound.text) ?? 0,
    unowned: parseAssetCount(unowned.text) ?? 0,
  );

  void dispose() {
    name.dispose();
    total.dispose();
    atRisk.dispose();
    newlyFound.dispose();
    unowned.dispose();
  }
}

class _AssetOverviewEditorState extends State<AssetOverviewEditor> {
  late final TextEditingController _title;
  late List<_GroupControllers> _groups;

  @override
  void initState() {
    super.initState();
    final spec = AssetOverviewSpec.fromSlide(
      widget.slide.title,
      widget.slide.tableRows,
    );
    _title = TextEditingController(text: spec.title)..addListener(_onChanged);
    _groups = spec.groups.map((g) => _GroupControllers(g, _onChanged)).toList();
    if (_groups.isEmpty) {
      _groups = [_GroupControllers(const AssetGroup(), _onChanged)];
    }
  }

  /// Unlike the other table editors, this one *shows* something derived from
  /// the fields — the running totals and the consistency warning. So a keystroke
  /// has to rebuild as well as emit, or the sums would sit there being wrong
  /// until the editor happened to be rebuilt for some other reason.
  void _onChanged() {
    if (mounted) setState(() {});
    _emit();
  }

  @override
  void dispose() {
    _title.dispose();
    for (final group in _groups) {
      group.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final spec = AssetOverviewSpec(
      title: _title.text.trim(),
      groups: _groups.map((g) => g.toGroup()).toList(),
    );
    widget.onUpdate(
      widget.slide.copyWith(title: spec.title, tableRows: spec.toTableRows()),
    );
  }

  void _addGroup() {
    setState(
      () => _groups.add(_GroupControllers(const AssetGroup(), _onChanged)),
    );
    _emit();
  }

  void _removeGroup(int index) {
    setState(() => _groups.removeAt(index).dispose());
    _emit();
  }

  void _moveGroup(int from, int to) {
    if (to < 0 || to >= _groups.length) return;
    setState(() => _groups.insert(to, _groups.removeAt(from)));
    _emit();
  }

  /// The sums the slide will show, recomputed as you type, so a mistyped figure
  /// is visible here rather than on the projector.
  AssetOverviewSpec get _current =>
      AssetOverviewSpec(groups: _groups.map((g) => g.toGroup()).toList());

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final full = _groups.length >= assetOverviewMaxGroups;
    final spec = _current;
    final inconsistent = spec.groups.any((g) => !g.isConsistent);

    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        EditorField(
          label: 'Titel',
          controller: _title,
          hint: 'Ons aanvalsoppervlak',
        ),
        const SizedBox(height: 12),
        _totalsBanner(context, spec, inconsistent),
        const SizedBox(height: 12),
        for (var i = 0; i < _groups.length; i++) ...[
          _groupCard(context, i),
          const SizedBox(height: 12),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: full
                ? l10n.d(
                    'Een overzicht draagt hoogstens acht soorten; meer is een inventarislijst en geen overzicht.',
                  )
                : '',
            child: OutlinedButton.icon(
              onPressed: full ? null : _addGroup,
              icon: const Icon(Icons.add, size: 16),
              label: Text(l10n.d('Soort toevoegen')),
            ),
          ),
        ),
      ],
    );
  }

  Widget _totalsBanner(
    BuildContext context,
    AssetOverviewSpec spec,
    bool inconsistent,
  ) {
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        border: Border.all(color: AppTheme.slate300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${spec.totalAssets} ${l10n.d('objecten in beeld')} · '
            '${spec.totalAtRisk} ${l10n.d('werk')} · '
            '${spec.totalNew} ${l10n.d('nieuw')} · '
            '${spec.totalUnowned} ${l10n.d('geen eigenaar')}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate600,
            ),
          ),
          if (inconsistent) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: AppTheme.danger700,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.d(
                      'Een deelgetal is groter dan het totaal van zijn soort. De slide toont het zoals ingevuld — controleer de bron.',
                    ),
                    style: TextStyle(fontSize: 11, color: AppTheme.danger700),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _groupCard(BuildContext context, int index) {
    final l10n = context.l10n;
    final group = _groups[index];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.slate300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: EditorField(
                  label: 'Soort object',
                  controller: group.name,
                  hint: 'Webapplicaties',
                ),
              ),
              IconButton(
                tooltip: l10n.d('Omhoog'),
                onPressed: index > 0
                    ? () => _moveGroup(index, index - 1)
                    : null,
                icon: const Icon(Icons.arrow_upward, size: 18),
                color: AppTheme.slate500,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: l10n.d('Omlaag'),
                onPressed: index < _groups.length - 1
                    ? () => _moveGroup(index, index + 1)
                    : null,
                icon: const Icon(Icons.arrow_downward, size: 18),
                color: AppTheme.slate500,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: l10n.d('Soort verwijderen'),
                onPressed: _groups.length > 1
                    ? () => _removeGroup(index)
                    : null,
                icon: const Icon(Icons.delete_outline, size: 18),
                color: AppTheme.slate500,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: EditorField(
                  label: 'Gevonden',
                  controller: group.total,
                  hint: '182',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: EditorField(
                  label: 'Kost werk',
                  controller: group.atRisk,
                  hint: '12',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: EditorField(
                  label: l10n.d('Nieuw'),
                  controller: group.newlyFound,
                  hint: '7',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: EditorField(
                  label: 'Geen eigenaar',
                  controller: group.unowned,
                  hint: '3',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l10n.d(
              'De drie laatste zijn deelverzamelingen van het gevonden aantal; OciDeck telt niets zelf, de cijfers komen uit uw scan.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ],
      ),
    );
  }
}
