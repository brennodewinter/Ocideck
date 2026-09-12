import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../services/import/logo_detection.dart';
import '../../utils/image_limits.dart';

class ImportLogoChoice {
  const ImportLogoChoice.notLogo()
    : isLogo = false,
      addAsStyle = false,
      styleName = '';

  const ImportLogoChoice.logo({required this.addAsStyle, this.styleName = ''})
    : isLogo = true;

  final bool isLogo;
  final bool addAsStyle;
  final String styleName;
}

/// Vraagt alleen bij een onbekende herhaalde randafbeelding of dit een logo is.
/// Een exacte overeenkomst met een bestaand stijlprofiel wordt buiten deze
/// dialoog afgehandeld: dan is er geen twijfel en voegt een vraag alleen werk
/// toe.
class ImportLogoDialog {
  const ImportLogoDialog._();

  static Future<ImportLogoChoice> ask(
    BuildContext context, {
    required ImportLogoCandidate candidate,
    required String suggestedStyleName,
    bool canAddAsStyle = true,
  }) async {
    final isLogo = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final l10n = context.l10n;
        final location = candidate.edge == ImportLogoEdge.top
            ? l10n.d('bovenaan')
            : l10n.d('onderaan');
        return AlertDialog(
          title: Text(l10n.d('Is dit een logo?')),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n
                      .d(
                        'Deze afbeelding staat op {n} dia’s {plaats}. OciDeck kan hem als vast logo gebruiken in plaats van als dia-afbeelding.',
                      )
                      .replaceAll('{n}', '${candidate.occurrenceCount}')
                      .replaceAll('{plaats}', location),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Semantics(
                    image: true,
                    label: l10n.d('Mogelijk logo'),
                    child: Image(
                      image: cappedMemoryImage(candidate.image.bytes),
                      width: 240,
                      height: 120,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                if (!canAddAsStyle) ...[
                  const SizedBox(height: 12),
                  Center(child: Text(l10n.d('Alleen in deze presentatie'))),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.d('Als afbeelding behouden')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.d('Ja, als logo gebruiken')),
            ),
          ],
        );
      },
    );
    if (isLogo != true || !context.mounted) {
      return const ImportLogoChoice.notLogo();
    }
    if (!canAddAsStyle) {
      return const ImportLogoChoice.logo(addAsStyle: false);
    }
    return _askToSaveStyle(context, suggestedStyleName);
  }

  static Future<ImportLogoChoice> _askToSaveStyle(
    BuildContext context,
    String suggestedStyleName,
  ) async {
    final choice = await showDialog<ImportLogoChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _SaveImportedStyleDialog(suggestedStyleName: suggestedStyleName),
    );
    return choice ?? const ImportLogoChoice.logo(addAsStyle: false);
  }
}

class _SaveImportedStyleDialog extends StatefulWidget {
  const _SaveImportedStyleDialog({required this.suggestedStyleName});

  final String suggestedStyleName;

  @override
  State<_SaveImportedStyleDialog> createState() =>
      _SaveImportedStyleDialogState();
}

class _SaveImportedStyleDialogState extends State<_SaveImportedStyleDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.suggestedStyleName)
      ..addListener(_changed);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = _controller.text.trim();
    return AlertDialog(
      title: Text(l10n.d('Ook als stijl toevoegen?')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Je kunt de kleuren, het lettertype en dit logo bewaren voor volgende presentaties.',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.d('Naam van de stijl'),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: name.isEmpty ? null : (value) => _save(value.trim()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            const ImportLogoChoice.logo(addAsStyle: false),
          ),
          child: Text(l10n.d('Alleen in deze presentatie')),
        ),
        FilledButton(
          onPressed: name.isEmpty ? null : () => _save(_controller.text.trim()),
          child: Text(l10n.d('Stijl toevoegen')),
        ),
      ],
    );
  }

  void _save(String name) => Navigator.pop(
    context,
    ImportLogoChoice.logo(addAsStyle: true, styleName: name),
  );
}
