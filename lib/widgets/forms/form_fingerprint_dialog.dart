// De vingerafdruk van de organisator vragen (FORM_INTAKE.md §5.1): wat de invuller in de
// uitnodiging las en nu intikt. Hij staat bewust niet in het bundelbestand — zonder hem kan een
// bundel niet laten zien van wie hij komt — en wordt hier dus nooit voorgevuld.

import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';

/// Vraagt de vingerafdruk; geeft wat er is ingetikt, of `null` bij annuleren.
Future<String?> askFormFingerprint(BuildContext context) => showDialog<String>(
  context: context,
  builder: (_) => const FormFingerprintDialog(),
);

class FormFingerprintDialog extends StatefulWidget {
  const FormFingerprintDialog({super.key});

  @override
  State<FormFingerprintDialog> createState() => _FormFingerprintDialogState();
}

class _FormFingerprintDialogState extends State<FormFingerprintDialog> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Semantics(
        header: true,
        child: Text(l10n.d('Vingerafdruk van de organisator')),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Typ de vingerafdruk uit de uitnodiging. Hij staat bewust niet in het bundelbestand: zo kun je nagaan van wie het komt.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(labelText: l10n.d('Vingerafdruk')),
              onSubmitted: (value) => Navigator.of(context).pop(value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Annuleren')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_text.text),
          child: Text(l10n.d('Doorgaan')),
        ),
      ],
    );
  }
}
