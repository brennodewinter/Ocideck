import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/deck.dart';

/// Wat de gebruiker bij het zetten van een TLP-niveau invulde (#2396).
class TlpAudienceChoice {
  const TlpAudienceChoice({
    required this.recipients,
    required this.note,
    required this.insertExplanation,
    required this.insertSlide,
  });

  final String recipients;
  final String note;
  final bool insertExplanation;
  final bool insertSlide;
}

/// AMBER+STRICT en RED mogen pas de markering schrijven als er ontvangers zijn.
bool tlpRequiresRecipients(TlpLevel level) =>
    level == TlpLevel.amberStrict || level == TlpLevel.red;

/// De FIRST-zin in de taal van de interface op het moment van invoegen.
String tlpStandardSentence(
  AppLocalizations l10n,
  TlpLevel level,
) => switch (level) {
  TlpLevel.clear => l10n.d(
    'TLP:CLEAR — ontvangers mogen deze informatie binnen hun gemeenschap verspreiden.',
  ),
  TlpLevel.green => l10n.d(
    'TLP:GREEN — beperkte verspreiding, alleen binnen de gemeenschap.',
  ),
  TlpLevel.amber => l10n.d(
    'TLP:AMBER — beperkte verspreiding, alleen binnen de organisaties van de deelnemers.',
  ),
  TlpLevel.amberStrict => l10n.d(
    'TLP:AMBER+STRICT — beperkte verspreiding, alleen voor de deelnemers.',
  ),
  TlpLevel.red => l10n.d(
    'TLP:RED — niet verder verspreiden, alleen voor de genoemde ontvangers.',
  ),
  TlpLevel.none => '',
};

/// Vraagt voor wie de markering is. `null` = geannuleerd, het niveau blijft.
Future<TlpAudienceChoice?> showTlpAudienceDialog(
  BuildContext context, {
  required TlpLevel level,
  bool offerParagraph = true,
  bool offerSlide = false,
}) {
  return showDialog<TlpAudienceChoice>(
    context: context,
    builder: (context) => _TlpAudienceDialog(
      level: level,
      offerParagraph: offerParagraph,
      offerSlide: offerSlide,
    ),
  );
}

class _TlpAudienceDialog extends StatefulWidget {
  const _TlpAudienceDialog({
    required this.level,
    required this.offerParagraph,
    required this.offerSlide,
  });

  final TlpLevel level;
  final bool offerParagraph;
  final bool offerSlide;

  @override
  State<_TlpAudienceDialog> createState() => _TlpAudienceDialogState();
}

class _TlpAudienceDialogState extends State<_TlpAudienceDialog> {
  final _recipients = TextEditingController();
  final _note = TextEditingController();
  var _insertExplanation = true;
  var _insertSlide = false;

  @override
  void initState() {
    super.initState();
    _insertExplanation = widget.offerParagraph;
  }

  @override
  void dispose() {
    _recipients.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final needsPeople = tlpRequiresRecipients(widget.level);
    final people = _recipients.text.trim();
    final canConfirm = !needsPeople || people.isNotEmpty;
    return AlertDialog(
      title: Text(l10n.d('Voor wie is deze classificatie?')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tlpStandardSentence(l10n, widget.level)),
            const SizedBox(height: 12),
            TextField(
              key: const Key('tlp-recipients'),
              controller: _recipients,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.d('Ontvangers'),
                hintText: l10n.d('Namen, gescheiden door komma\'s'),
                errorText: needsPeople && people.isEmpty
                    ? l10n.d('Vul in voor wie dit bestemd is.')
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('tlp-note'),
              controller: _note,
              decoration: InputDecoration(
                labelText: l10n.d('Toelichting (optioneel)'),
              ),
            ),
            if (widget.offerParagraph)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _insertExplanation,
                onChanged: (v) =>
                    setState(() => _insertExplanation = v ?? false),
                title: Text(
                  l10n.d('Standaardtoelichting in het document zetten'),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            if (widget.offerSlide)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _insertSlide,
                onChanged: (v) => setState(() => _insertSlide = v ?? false),
                title: Text(l10n.d('Als dia invoegen')),
                controlAffinity: ListTileControlAffinity.leading,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.t('cancel')),
        ),
        FilledButton(
          key: const Key('tlp-audience-confirm'),
          onPressed: canConfirm
              ? () => Navigator.pop(
                  context,
                  TlpAudienceChoice(
                    recipients: people,
                    note: _note.text.trim(),
                    insertExplanation: _insertExplanation,
                    insertSlide: _insertSlide,
                  ),
                )
              : null,
          child: Text(l10n.t('save')),
        ),
      ],
    );
  }
}
