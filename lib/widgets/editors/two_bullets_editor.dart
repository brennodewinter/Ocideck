import 'package:material_ui/material_ui.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../l10n/app_localizations.dart';
import '_editor_field.dart';
import 'bullet_editor_items.dart';
import 'bullet_marker_selector.dart';
import 'list_style_selector.dart';
import 'split_continuation_switch.dart';
import 'editor_text_controller.dart';

class TwoBulletsEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;

  /// Of de vorige slide met deze een gesplitste reeks kan vormen — bepaalt of
  /// de voortzettingsschakelaar zin heeft.
  final bool canContinueSplit;

  final bool nestedInScrollView;

  const TwoBulletsEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.canContinueSplit = false,
    this.nestedInScrollView = false,
  });

  @override
  State<TwoBulletsEditor> createState() => _TwoBulletsEditorState();
}

class _TwoBulletsEditorState extends State<TwoBulletsEditor> {
  late final EditorTextController _title;
  late final EditorTextController _heading1;
  late final EditorTextController _heading2;
  late final BulletSet _left;
  late final BulletSet _right;
  late ListStyle _listStyle;
  BulletMarker? _bulletMarkerOverride;
  late bool _showChecklistProgress;
  late bool _continuesSplit;

  @override
  void initState() {
    super.initState();
    _title = EditorTextController(text: widget.slide.title);
    _title.addTextListener(_emit);
    _heading1 = EditorTextController(text: widget.slide.columnTitle1);
    _heading2 = EditorTextController(text: widget.slide.columnTitle2);
    _heading1.addTextListener(_emit);
    _heading2.addTextListener(_emit);
    _listStyle = widget.slide.listStyle == ListStyle.richText
        ? ListStyle.bullets
        : widget.slide.listStyle;
    _bulletMarkerOverride = widget.slide.bulletMarkerOverride;
    _showChecklistProgress = widget.slide.showChecklistProgress;
    _continuesSplit = widget.slide.continuesSplit;
    _left = BulletSet(widget.slide.bullets, _emit);
    _right = BulletSet(widget.slide.bullets2, _emit);
  }

  void _emit() {
    widget.onUpdate(
      widget.slide.copyWith(
        title: _title.text,
        columnTitle1: _heading1.text,
        columnTitle2: _heading2.text,
        listStyle: _listStyle,
        bulletMarkerOverride: _bulletMarkerOverride,
        clearBulletMarkerOverride: _bulletMarkerOverride == null,
        showChecklistProgress: _showChecklistProgress,
        // Alleen een slide die daadwerkelijk op een gelijksoortige voorganger
        // volgt kan een voortzetting zijn.
        continuesSplit: widget.canContinueSplit && _continuesSplit,
        bullets: _left.values(_listStyle),
        bullets2: _right.values(_listStyle),
      ),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _heading1.dispose();
    _heading2.dispose();
    _left.dispose();
    _right.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        EditorField(label: 'Titel', controller: _title, hint: 'Slide titel'),
        const SizedBox(height: 16),
        ListStyleSelector(
          value: _listStyle,
          allowRichText: false,
          onChanged: (value) {
            setState(() => _listStyle = value);
            _emit();
          },
        ),
        if (_listStyle == ListStyle.bullets) ...[
          const SizedBox(height: 12),
          BulletMarkerSelector(
            value: _bulletMarkerOverride,
            onChanged: (value) {
              setState(() => _bulletMarkerOverride = value);
              _emit();
            },
          ),
        ],
        if (widget.canContinueSplit)
          SplitContinuationSwitch(
            value: _continuesSplit,
            onChanged: (value) {
              setState(() => _continuesSplit = value);
              _emit();
            },
          ),
        if (_listStyle == ListStyle.checklist)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.d('Voortgangsgrafiek tonen')),
            subtitle: Text(
              context.l10n.d(
                'Toont afgevinkt en niet afgevinkt als percentages.',
              ),
            ),
            value: _showChecklistProgress,
            onChanged: (value) {
              setState(() => _showChecklistProgress = value);
              _emit();
            },
          ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 560;
            final columns = [
              _BulletColumn(
                label: 'Bullets links',
                set: _left,
                headingController: _heading1,
                listStyle: _listStyle,
              ),
              _BulletColumn(
                label: 'Bullets rechts',
                set: _right,
                headingController: _heading2,
                listStyle: _listStyle,
              ),
            ];
            if (narrow) {
              return Column(
                children: [columns[0], const SizedBox(height: 18), columns[1]],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: columns[0]),
                const SizedBox(width: 16),
                Expanded(child: columns[1]),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _BulletColumn extends StatefulWidget {
  final String label;
  final BulletSet set;
  final EditorTextController headingController;
  final ListStyle listStyle;

  const _BulletColumn({
    required this.label,
    required this.set,
    required this.headingController,
    required this.listStyle,
  });

  @override
  State<_BulletColumn> createState() => _BulletColumnState();
}

class _BulletColumnState extends State<_BulletColumn> {
  BulletSet get set => widget.set;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.headingController,
          decoration: InputDecoration(
            labelText: l10n.d('Kop (optioneel)'),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        SectionLabel(widget.label),
        const SizedBox(height: 6),
        for (int i = 0; i < set.controllers.length; i++)
          BulletEditorRow(
            key: ValueKey(set.controllers[i]),
            bullets: set,
            index: i,
            listStyle: widget.listStyle,
            mutate: (mutation) => setState(mutation),
            keyPrefix: widget.label,
          ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              onPressed: () => set.addAfter(
                (fn) => setState(fn),
                set.controllers.length - 1,
              ),
              icon: const Icon(Icons.add, size: 16),
              label: Text(l10n.d('Bullet toevoegen')),
            ),
            TextButton.icon(
              onPressed: () => set.addAfter(
                (fn) => setState(fn),
                set.controllers.length - 1,
                heading: true,
              ),
              icon: const Icon(Icons.horizontal_split, size: 16),
              label: Text(l10n.d('Tussenkop toevoegen')),
            ),
          ],
        ),
      ],
    );
  }
}
