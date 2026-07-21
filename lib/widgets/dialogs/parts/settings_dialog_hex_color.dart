// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (the custom hex-colour picker dialog); all
// imports live in the main library file. Same library, same members, no
// behaviour change.
part of '../settings_dialog.dart';

class _HexColorDialog extends StatefulWidget {
  final String initial;

  const _HexColorDialog({required this.initial});

  @override
  State<_HexColorDialog> createState() => _HexColorDialogState();
}

class _HexColorDialogState extends State<_HexColorDialog> {
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

  String? _normalize(String raw) {
    final up = raw.trim().toUpperCase();
    final hex = up.startsWith('#') ? up : '#$up';
    return RegExp(r'^#[0-9A-F]{6}$').hasMatch(hex) ? hex : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final normalized = _normalize(_controller.text);
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
                  color: _parseHexColor(normalized ?? '#FFFFFF'),
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
                    final ok = _normalize(_controller.text);
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
