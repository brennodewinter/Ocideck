import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/color_contrast.dart';

/// Een eigen kleur intikken als hexwaarde, met een voorbeeldvlak dat meeloopt
/// met wat er staat.
///
/// Een eigen dialoogbestand en geen `part` van het instellingenvenster: de
/// normalisatie hieronder is het enige dat tussen "wat de gebruiker tikt" en
/// "welke kleur het thema krijgt" zit, en als deel van die bibliotheek was daar
/// van buiten geen woord over te zeggen. Zelfde reden als bij
/// `GitSearchDialog`.
class HexColorDialog extends StatefulWidget {
  /// De kleur waarmee het veld begint, als hexwaarde.
  final String initial;

  const HexColorDialog({super.key, required this.initial});

  /// Toont het venster en geeft de genormaliseerde kleur terug (`#RRGGBB`,
  /// hoofdletters), of `null` bij annuleren.
  static Future<String?> show(BuildContext context, String initial) =>
      showDialog<String>(
        context: context,
        builder: (_) => HexColorDialog(initial: initial),
      );

  /// De ingetikte waarde als `#RRGGBB` in hoofdletters, of `null` wanneer het
  /// geen volledige hexkleur is.
  ///
  /// Publiek omdat dit de hele regel is: het hekje mag weg, spaties en
  /// kleine letters mogen, maar een halve kleur (`#33FF`) is geen kleur en
  /// hoort het thema niet te bereiken.
  static String? normalize(String raw) {
    final up = raw.trim().toUpperCase();
    final hex = up.startsWith('#') ? up : '#$up';
    return RegExp(r'^#[0-9A-F]{6}$').hasMatch(hex) ? hex : null;
  }

  @override
  State<HexColorDialog> createState() => _HexColorDialogState();
}

class _HexColorDialogState extends State<HexColorDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final normalized = HexColorDialog.normalize(_controller.text);
    return AlertDialog(
      title: Text(l10n.d('Eigen kleur (hex)')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  // Onleesbaar getikte tekst laat het vlak wit, zodat het
                  // voorbeeld nooit een kleur toont die niet gekozen kan worden.
                  color: parseHexColor(normalized) ?? const Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.slate300),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l10n.d('Hexkleur'),
                    hintText: l10n.d('#33FF33'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
                    LengthLimitingTextInputFormatter(7),
                  ],
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    final ok = HexColorDialog.normalize(_controller.text);
                    if (ok != null) Navigator.pop(context, ok);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.d('Bijvoorbeeld #33FF33 voor een CRT-groen scherm.'),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.d('Annuleren')),
        ),
        FilledButton(
          onPressed: normalized == null
              ? null
              : () => Navigator.pop(context, normalized),
          child: Text(l10n.d('Toepassen')),
        ),
      ],
    );
  }
}
