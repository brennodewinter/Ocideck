import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/image_callout.dart';
import '../../models/slide.dart';
import 'list_style_selector.dart';

/// Dezelfde instelling voor gewone bullets en bullets naast een afbeelding.
class BulletRevealSelector extends StatelessWidget {
  const BulletRevealSelector({
    super.key,
    required this.slide,
    required this.onUpdate,
    required this.listStyle,
    required this.onListStyleChanged,
  });
  final Slide slide;
  final ListStyle listStyle;
  final ValueChanged<ListStyle> onListStyleChanged;
  final ValueChanged<Slide> onUpdate;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListStyleSelector(value: listStyle, onChanged: onListStyleChanged),
      if (listStyle != ListStyle.richText)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.d('Stap-voor-stap')),
          subtitle: Text(context.l10n.d('Tijdens presenteren')),
          value: slide.calloutReveal == BulletRevealMode.steps,
          onChanged: (enabled) => onUpdate(
            slide.copyWith(
              calloutReveal: enabled
                  ? BulletRevealMode.steps
                  : BulletRevealMode.all,
            ),
          ),
        ),
    ],
  );
}
