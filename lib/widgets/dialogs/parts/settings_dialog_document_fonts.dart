// Part of the settings_dialog library — see ../settings_dialog.dart.
//
// De letterinstellingen die #2119 aan een stijl toevoegde: het gewenste
// lettertype (de naam die een export noemt, ook als OciDeck hem zelf niet kan
// tonen) en de kopletter van een document. Zelfstandige widgets, geen leden
// van de instellingen-State: ze lezen alleen een waarde en melden een nieuwe,
// en de State zit tegen haar plafond.

part of '../settings_dialog.dart';

/// Een tekstveld voor een gewenst lettertype ([ThemeProfile.preferredFontFamily]
/// of de kopvariant). Leeg betekent "geen voorkeur": dan noemt de export wat
/// het scherm toont. Een naam die niet door [kPreferredFontFamilyPattern]
/// komt wordt niet bewaard en krijgt een foutmelding — dezelfde poort als de
/// lezer van het profiel, zodat wat je hier ziet ook is wat er opgeslagen is.
class _PreferredFontField extends StatefulWidget {
  const _PreferredFontField({
    super.key,
    required this.value,
    required this.label,
    required this.helper,
    required this.onChanged,
  });

  final String? value;
  final String label;
  final String helper;

  /// Krijgt de gesaneerde naam, of `null` wanneer het veld leeg is.
  final ValueChanged<String?> onChanged;

  @override
  State<_PreferredFontField> createState() => _PreferredFontFieldState();
}

class _PreferredFontFieldState extends State<_PreferredFontField> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value ?? '');
  }

  @override
  void didUpdateWidget(covariant _PreferredFontField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Een ander profiel gekozen: het veld volgt, zonder de cursor te storen
    // terwijl iemand typt (dan is de tekst al gelijk).
    final next = widget.value ?? '';
    if (widget.value != oldWidget.value && _controller.text.trim() != next) {
      _controller.text = next;
      _error = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _changed(String raw) {
    final name = raw.trim();
    if (name.isEmpty) {
      setState(() => _error = null);
      widget.onChanged(null);
      return;
    }
    if (!kPreferredFontFamilyPattern.hasMatch(name)) {
      setState(
        () => _error = context.l10n.d(
          'Alleen letters, cijfers, spaties, punten en koppeltekens.',
        ),
      );
      return;
    }
    setState(() => _error = null);
    widget.onChanged(name);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      controller: _controller,
      onChanged: _changed,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        helperMaxLines: 3,
        errorText: _error,
        isDense: true,
      ),
    ),
  );
}

/// De kopletter van een document: dezelfde lijst als het lettertype, met
/// vooraan de keuze om de koppen de lopende tekst te laten volgen — de stand
/// die er altijd was en die `null` in het profiel blijft.
class _DocumentHeadingFontPicker extends StatelessWidget {
  const _DocumentHeadingFontPicker({
    required this.selected,
    required this.bodyFont,
    required this.onSelected,
  });

  /// `null` = volgt de lopende tekst.
  final String? selected;
  final String bodyFont;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final options = <String?>[null, ...AppSettings.availableFonts];
    return Container(
      key: const Key('document-heading-font'),
      decoration: _boxDecoration(context),
      child: Column(
        children: [
          for (final font in options)
            InkWell(
              key: Key('document-heading-font-${font ?? 'body'}'),
              onTap: () => onSelected(font),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: font == selected
                      ? AppTheme.accent.withValues(alpha: 0.08)
                      : Colors.transparent,
                  border: Border(
                    bottom: BorderSide(
                      color: AppTheme.slate200,
                      width: font == options.last ? 0 : 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        font ??
                            l10n
                                .d('Zelfde als de tekst ({letter})')
                                .replaceAll('{letter}', bodyFont),
                        style: _fontStyle(
                          font ?? bodyFont,
                          TextStyle(
                            fontSize: 14,
                            color: font == selected
                                ? AppTheme.accentFg
                                : AppTheme.slate700,
                            fontWeight: font == selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                    if (font == selected)
                      Icon(Icons.check, size: 16, color: AppTheme.accentFg),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
