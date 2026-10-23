import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/settings.dart';
import '../../services/import/logo_detection.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_limits.dart';

/// Preview the values OciDeck can actually render before storing a template.
class ImportTemplateStyleDialog extends StatefulWidget {
  const ImportTemplateStyleDialog({
    super.key,
    required this.profile,
    required this.suggestedName,
    required this.importedDetails,
    required this.omittedDetails,
    required this.existingNames,
    this.logoCandidate,
  });

  final ThemeProfile profile;
  final String suggestedName;
  final List<String> importedDetails;
  final List<String> omittedDetails;
  final Set<String> existingNames;
  final ImportLogoCandidate? logoCandidate;

  static Future<({String name, bool useLogo})?> ask(
    BuildContext context, {
    required ThemeProfile profile,
    required String suggestedName,
    required List<String> importedDetails,
    required List<String> omittedDetails,
    required Set<String> existingNames,
    ImportLogoCandidate? logoCandidate,
  }) => showDialog<({String name, bool useLogo})>(
    context: context,
    builder: (context) => ImportTemplateStyleDialog(
      profile: profile,
      suggestedName: suggestedName,
      importedDetails: importedDetails,
      omittedDetails: omittedDetails,
      existingNames: existingNames,
      logoCandidate: logoCandidate,
    ),
  );

  @override
  State<ImportTemplateStyleDialog> createState() =>
      _ImportTemplateStyleDialogState();
}

class _ImportTemplateStyleDialogState extends State<ImportTemplateStyleDialog> {
  late final TextEditingController _name;
  bool _useLogo = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.suggestedName)
      ..addListener(_changed);
  }

  @override
  void dispose() {
    _name
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final profile = widget.profile;
    return AlertDialog(
      title: Text(l10n.d('PowerPoint-sjabloon als stijl importeren')),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.d('Voorbeeld van de OciDeck-stijl')),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final (background, foreground, label) in [
                    (
                      profile.titleBackgroundColor,
                      profile.titleTextColor,
                      l10n.d('Titel'),
                    ),
                    (
                      profile.slideBackgroundColor,
                      profile.textColor,
                      l10n.d('Inhoud'),
                    ),
                    (
                      profile.sectionBackgroundColor,
                      profile.titleTextColor,
                      l10n.d('Sectie'),
                    ),
                  ])
                    Expanded(
                      child: Container(
                        height: 68,
                        margin: const EdgeInsets.only(right: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.parseHexColor(background),
                          border: Border.all(color: Colors.black26),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: AppTheme.parseHexColor(foreground),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(l10n.d('Overgenomen:')),
              for (final detail in widget.importedDetails) Text('• $detail'),
              const SizedBox(height: 8),
              Text(l10n.d('Niet overgenomen:')),
              for (final detail in widget.omittedDetails) Text('• $detail'),
              if (widget.logoCandidate case final candidate?) ...[
                const SizedBox(height: 12),
                Center(
                  child: Semantics(
                    image: true,
                    label: l10n.d('Mogelijk logo'),
                    child: Image(
                      image: cappedMemoryImage(candidate.image.bytes),
                      width: 180,
                      height: 90,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                CheckboxListTile(
                  value: _useLogo,
                  onChanged: (value) =>
                      setState(() => _useLogo = value ?? false),
                  title: Text(l10n.d('Dit beeld als vast logo gebruiken')),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.d('Naam van stijl'),
                  errorText: widget.existingNames.contains(_name.text.trim())
                      ? l10n.d('Deze stijlnaam bestaat al.')
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.d('Annuleren')),
        ),
        FilledButton(
          onPressed:
              _name.text.trim().isEmpty ||
                  widget.existingNames.contains(_name.text.trim())
              ? null
              : () => Navigator.pop(context, (
                  name: _name.text.trim(),
                  useLogo: _useLogo,
                )),
          child: Text(l10n.d('Stijl bewaren')),
        ),
      ],
    );
  }
}
