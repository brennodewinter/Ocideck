import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/discoveries_spec.dart';
import '../../models/slide.dart';
import '../../theme/app_theme.dart';
import '_editor_field.dart';
import 'editor_text_controller.dart';

/// Editor for a `discoveries` slide: a title plus up to [discoveriesMaxEntries]
/// newly found objects, each with what kind of thing it is, how long it sat
/// there unnoticed and who owns it now. Emits the slide title and `tableRows`
/// via [DiscoveriesSpec]; storage stays a Markdown table.
///
/// Like the asset overview, nothing here is measured by OciDeck — the figures
/// come from whatever tool produced the report, which is why the table form
/// matters: a generator can write it directly and a human can read it without
/// the app.
///
/// The banner restates what the slide will lead with, recomputed as you type. It
/// is the one place an author can see that a mistyped exposure has taken over
/// the headline, before the slide reaches a projector.
class DiscoveriesEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final bool nestedInScrollView;

  const DiscoveriesEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.nestedInScrollView = false,
  });

  @override
  State<DiscoveriesEditor> createState() => _DiscoveriesEditorState();
}

class _DiscoveryControllers {
  _DiscoveryControllers(Discovery discovery, VoidCallback onChanged)
    : name = EditorTextController(text: discovery.name)
        ..addTextListener(onChanged),
      kind = EditorTextController(text: discovery.kind)
        ..addTextListener(onChanged),
      days = EditorTextController(
        text: discovery.daysUnnoticed == null
            ? ''
            : '${discovery.daysUnnoticed}',
      )..addTextListener(onChanged),
      owner = EditorTextController(text: discovery.owner)
        ..addTextListener(onChanged);

  final EditorTextController name;
  final EditorTextController kind;
  final EditorTextController days;
  final EditorTextController owner;

  Discovery toDiscovery() => Discovery(
    name: name.text.trim(),
    kind: kind.text.trim(),
    daysUnnoticed: parseDaysUnnoticed(days.text),
    owner: owner.text.trim(),
  );

  void dispose() {
    name.dispose();
    kind.dispose();
    days.dispose();
    owner.dispose();
  }
}

class _DiscoveriesEditorState extends State<DiscoveriesEditor> {
  late final EditorTextController _title;
  late List<_DiscoveryControllers> _discoveries;

  @override
  void initState() {
    super.initState();
    final spec = DiscoveriesSpec.fromSlide(
      widget.slide.title,
      widget.slide.tableRows,
    );
    _title = EditorTextController(text: spec.title)
      ..addTextListener(_onChanged);
    _discoveries = spec.discoveries
        .map((d) => _DiscoveryControllers(d, _onChanged))
        .toList();
    if (_discoveries.isEmpty) {
      _discoveries = [_DiscoveryControllers(const Discovery(), _onChanged)];
    }
  }

  /// The banner shows something derived from the fields, so a keystroke has to
  /// rebuild as well as emit — otherwise the headline would sit there being
  /// wrong until the editor happened to rebuild for some other reason. The same
  /// reason the asset overview editor does it.
  void _onChanged() {
    if (mounted) setState(() {});
    _emit();
  }

  @override
  void dispose() {
    _title.dispose();
    for (final discovery in _discoveries) {
      discovery.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final spec = DiscoveriesSpec(
      title: _title.text.trim(),
      discoveries: _discoveries.map((d) => d.toDiscovery()).toList(),
    );
    widget.onUpdate(
      widget.slide.copyWith(title: spec.title, tableRows: spec.toTableRows()),
    );
  }

  void _addDiscovery() {
    setState(
      () => _discoveries.add(
        _DiscoveryControllers(const Discovery(), _onChanged),
      ),
    );
    _emit();
  }

  void _removeDiscovery(int index) {
    setState(() => _discoveries.removeAt(index).dispose());
    _emit();
  }

  void _moveDiscovery(int from, int to) {
    if (to < 0 || to >= _discoveries.length) return;
    setState(() => _discoveries.insert(to, _discoveries.removeAt(from)));
    _emit();
  }

  DiscoveriesSpec get _current => DiscoveriesSpec(
    discoveries: _discoveries.map((d) => d.toDiscovery()).toList(),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final full = _discoveries.length >= discoveriesMaxEntries;

    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        EditorField(
          label: 'Titel',
          controller: _title,
          hint: 'Wat we niet wisten te hebben',
        ),
        const SizedBox(height: 12),
        _headlineBanner(context, _current),
        const SizedBox(height: 12),
        for (var i = 0; i < _discoveries.length; i++) ...[
          _discoveryCard(context, i),
          const SizedBox(height: 12),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: full
                ? l10n.d(
                    'Zes ontdekkingen is het maximum; wie er meer noemt maakt een bijlage in plaats van een slide.',
                  )
                : '',
            child: OutlinedButton.icon(
              onPressed: full ? null : _addDiscovery,
              icon: const Icon(Icons.add, size: 16),
              label: Text(l10n.d('Ontdekking toevoegen')),
            ),
          ),
        ),
      ],
    );
  }

  /// What the slide will lead with, recomputed as you type.
  Widget _headlineBanner(BuildContext context, DiscoveriesSpec spec) {
    final l10n = context.l10n;
    final longest = spec.longestUnnoticed;
    final parts = [
      '${spec.count} '
          '${spec.count == 1 ? l10n.d('ontdekking') : l10n.d('ontdekkingen')}',
      if (spec.unownedCount > 0)
        '${spec.unownedCount} ${l10n.d('geen eigenaar')}',
    ];
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
            parts.join(' · '),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            longest == null
                ? l10n.d(
                    'Nog geen blootstelling ingevuld — de slide toont dan geen kop, alleen de lijst.',
                  )
                : '${l10n.d('Kop van de slide')}: $longest '
                      '${l10n.d('dagen onopgemerkt')}',
            style: TextStyle(
              fontSize: 11,
              color: longest == null ? AppTheme.slate400 : AppTheme.slate600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _discoveryCard(BuildContext context, int index) {
    final l10n = context.l10n;
    final discovery = _discoveries[index];
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
                  label: 'Wat is gevonden',
                  controller: discovery.name,
                  hint: 'betaalportaal-acc.example.nl',
                ),
              ),
              IconButton(
                tooltip: l10n.d('Omhoog'),
                onPressed: index > 0
                    ? () => _moveDiscovery(index, index - 1)
                    : null,
                icon: const Icon(Icons.arrow_upward, size: 18),
                color: AppTheme.slate500,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: l10n.d('Omlaag'),
                onPressed: index < _discoveries.length - 1
                    ? () => _moveDiscovery(index, index + 1)
                    : null,
                icon: const Icon(Icons.arrow_downward, size: 18),
                color: AppTheme.slate500,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: l10n.d('Ontdekking verwijderen'),
                onPressed: _discoveries.length > 1
                    ? () => _removeDiscovery(index)
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
                flex: 3,
                child: EditorField(
                  label: 'Soort',
                  controller: discovery.kind,
                  hint: 'Webapplicatie',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: EditorField(
                  label: 'Dagen onopgemerkt',
                  controller: discovery.days,
                  hint: '412',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: EditorField(
                  label: 'Eigenaar',
                  controller: discovery.owner,
                  hint: 'Team Betalen',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l10n.d(
              'Laat de dagen leeg als de eerste blootstelling onbekend is; de slide zegt dan "onbekend" in plaats van nul. Een lege eigenaar leest als "geen eigenaar" en valt rood op.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ],
      ),
    );
  }
}
