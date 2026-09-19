// De vraag na een documentimport: de huisstijl van de bron overnemen? (#2119)
//
// Eén dialoog, na het omzetten, alleen wanneer er iets te halen valt. Hij
// toont wat er in de bron stond én wat OciDeck ervan maakt — de letter die de
// huisstijl vraagt naast de plaatsvervanger op het scherm, de kleuren als
// stalen, het logo met zijn plek — en wat níét mee kan. De keuze is bewust
// optioneel: de stijl kan al bestaan, of bewust losgelaten worden.

import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../services/font_substitution.dart';
import '../../services/import/models/source_document_style.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_limits.dart';

/// Wat de gebruiker met de gevonden huisstijl doet.
enum ImportDocumentStyleDisposition {
  /// Alleen de tekst: geen stijl, geen `theme:` in het document.
  textOnly,

  /// Het profiel dat deze huisstijl al is, hergebruiken.
  useExisting,

  /// Een nieuw profiel bewaren en op het document zetten.
  newStyle,
}

class ImportDocumentStyleChoice {
  const ImportDocumentStyleChoice.textOnly()
    : disposition = ImportDocumentStyleDisposition.textOnly,
      styleName = '',
      includeLogo = false;

  const ImportDocumentStyleChoice.useExisting()
    : disposition = ImportDocumentStyleDisposition.useExisting,
      styleName = '',
      includeLogo = false;

  const ImportDocumentStyleChoice.newStyle({
    required this.styleName,
    required this.includeLogo,
  }) : disposition = ImportDocumentStyleDisposition.newStyle;

  final ImportDocumentStyleDisposition disposition;

  /// De naam van het nieuwe profiel (alleen bij [newStyle]).
  final String styleName;

  /// Of het gevonden beeld als documentlogo meegaat (alleen bij [newStyle]).
  final bool includeLogo;
}

/// Vraagt of de huisstijl van het brondocument overgenomen wordt.
class ImportDocumentStyleDialog {
  const ImportDocumentStyleDialog._();

  /// [existingStyleName] is het profiel dat deze huisstijl al is, als dat er
  /// is; dan biedt de dialoog hergebruik aan. [logoIsSessionOnly] zegt dat het
  /// logo niet blijvend bewaard kan worden (web): de stijl komt er wel, het
  /// beeld alleen voor deze sessie.
  static Future<ImportDocumentStyleChoice> ask(
    BuildContext context, {
    required SourceDocumentStyle style,
    required String suggestedStyleName,
    String? existingStyleName,
    bool logoIsSessionOnly = false,
  }) async {
    final choice = await showDialog<ImportDocumentStyleChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ImportDocumentStyleDialog(
        style: style,
        suggestedStyleName: suggestedStyleName,
        existingStyleName: existingStyleName,
        logoIsSessionOnly: logoIsSessionOnly,
      ),
    );
    return choice ?? const ImportDocumentStyleChoice.textOnly();
  }
}

class _ImportDocumentStyleDialog extends StatefulWidget {
  const _ImportDocumentStyleDialog({
    required this.style,
    required this.suggestedStyleName,
    required this.existingStyleName,
    required this.logoIsSessionOnly,
  });

  final SourceDocumentStyle style;
  final String suggestedStyleName;
  final String? existingStyleName;
  final bool logoIsSessionOnly;

  @override
  State<_ImportDocumentStyleDialog> createState() =>
      _ImportDocumentStyleDialogState();
}

class _ImportDocumentStyleDialogState
    extends State<_ImportDocumentStyleDialog> {
  late final TextEditingController _name;
  var _includeLogo = true;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.suggestedStyleName)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = widget.style;
    final logo = style.logoCandidates.firstOrNull;
    final name = _name.text.trim();
    return AlertDialog(
      title: Text(l10n.d('Stijl overnemen?')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.d(
                  'Het document draagt een eigen huisstijl. OciDeck kan die als stijl bewaren en op dit document toepassen.',
                ),
              ),
              if (widget.existingStyleName != null) ...[
                const SizedBox(height: 12),
                Text(
                  l10n
                      .d('Deze huisstijl bestaat al als de stijl {naam}.')
                      .replaceAll('{naam}', widget.existingStyleName!),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
              if (style.headingFontFamily != null ||
                  style.bodyFontFamily != null) ...[
                _sectionTitle(l10n.d('Lettertype')),
                if (style.headingFontFamily != null)
                  _fontRow(l10n, l10n.d('Koppen'), style.headingFontFamily!),
                if (style.bodyFontFamily != null)
                  _fontRow(l10n, l10n.d('Tekst'), style.bodyFontFamily!),
              ],
              if (style.textColor != null ||
                  style.headingColor != null ||
                  style.accentColor != null) ...[
                _sectionTitle(l10n.d('Kleuren')),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    if (style.textColor != null)
                      _swatch(l10n.d('Tekst'), style.textColor!),
                    if (style.headingColor != null)
                      _swatch(l10n.d('Koppen'), style.headingColor!),
                    if (style.accentColor != null)
                      _swatch(l10n.d('Accent'), style.accentColor!),
                  ],
                ),
              ],
              if (logo != null) ...[
                _sectionTitle(l10n.d('Logo')),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Semantics(
                      image: true,
                      label: l10n.d('Mogelijk logo'),
                      child: Container(
                        width: 120,
                        height: 64,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.slate300),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Image(
                          image: cappedMemoryImage(logo.bytes),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n
                            .d(
                              'Staat {plaats} op elke bladzijde, {mm} mm breed.',
                            )
                            .replaceAll('{plaats}', _placeLabel(l10n, logo))
                            .replaceAll(
                              '{mm}',
                              logo.widthMm.toStringAsFixed(0),
                            ),
                      ),
                    ),
                  ],
                ),
                CheckboxListTile(
                  key: const Key('import-document-style-logo'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _includeLogo,
                  onChanged: (value) =>
                      setState(() => _includeLogo = value ?? false),
                  title: Text(l10n.d('Als documentlogo gebruiken')),
                  subtitle: widget.logoIsSessionOnly
                      ? Text(
                          l10n.d(
                            'Op het web blijft het logo alleen deze sessie bewaard.',
                          ),
                        )
                      : null,
                ),
              ],
              if (style.headerText != null ||
                  style.footerText != null ||
                  style.showPageNumbers) ...[
                _sectionTitle(l10n.d('Kop- en voettekst')),
                if (style.headerText != null)
                  Text('${l10n.d('Koptekst')}: ${style.headerText}'),
                if (style.footerText != null)
                  Text('${l10n.d('Voettekst')}: ${style.footerText}'),
                if (style.showPageNumbers) Text(l10n.d('Paginanummers')),
              ],
              if (style.losses.isNotEmpty) ...[
                _sectionTitle(l10n.d('Niet overgenomen')),
                for (final loss in style.losses)
                  Text('• ${_lossLabel(l10n, loss)}'),
              ],
              const SizedBox(height: 16),
              TextField(
                key: const Key('import-document-style-name'),
                controller: _name,
                decoration: InputDecoration(
                  labelText: l10n.d('Naam van de stijl'),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: name.isEmpty ? null : (_) => _saveNew(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('import-document-style-text-only'),
          onPressed: () => Navigator.pop(
            context,
            const ImportDocumentStyleChoice.textOnly(),
          ),
          child: Text(l10n.d('Alleen tekst')),
        ),
        if (widget.existingStyleName != null) ...[
          TextButton(
            key: const Key('import-document-style-new'),
            onPressed: name.isEmpty ? null : _saveNew,
            child: Text(l10n.d('Nieuwe stijl toevoegen')),
          ),
          FilledButton(
            key: const Key('import-document-style-existing'),
            onPressed: () => Navigator.pop(
              context,
              const ImportDocumentStyleChoice.useExisting(),
            ),
            child: Text(l10n.d('Bestaande stijl gebruiken')),
          ),
        ] else
          FilledButton(
            key: const Key('import-document-style-new'),
            onPressed: name.isEmpty ? null : _saveNew,
            child: Text(l10n.d('Stijl overnemen')),
          ),
      ],
    );
  }

  void _saveNew() => Navigator.pop(
    context,
    ImportDocumentStyleChoice.newStyle(
      styleName: _name.text.trim(),
      includeLogo: _includeLogo && widget.style.logoCandidates.isNotEmpty,
    ),
  );

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
  );

  /// Eén letterregel: de naam uit de bron, en — als OciDeck die niet kan
  /// tonen — de plaatsvervanger erachter.
  Widget _fontRow(AppLocalizations l10n, String label, String family) {
    final standIn = nearestAvailableFont(family);
    final sameFont = standIn.toLowerCase() == family.trim().toLowerCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        sameFont
            ? '$label: $family'
            : '$label: $family ${l10n.d('(weergegeven als {vervanger}, bewaard voor export)').replaceAll('{vervanger}', standIn)}',
      ),
    );
  }

  Widget _swatch(String label, String hex) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: AppTheme.parseHexColor(hex),
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.slate300),
        ),
      ),
      const SizedBox(width: 6),
      Text('$label $hex'),
    ],
  );

  String _placeLabel(AppLocalizations l10n, DocumentLogoCandidate logo) {
    if (logo.centred) {
      return logo.edge == DocumentLogoEdge.top
          ? l10n.d('gecentreerd bovenaan')
          : l10n.d('gecentreerd onderaan');
    }
    return switch (logo.position) {
      'top-left' => l10n.d('linksboven'),
      'top-right' => l10n.d('rechtsboven'),
      'bottom-left' => l10n.d('linksonder'),
      _ => l10n.d('rechtsonder'),
    };
  }

  String _lossLabel(AppLocalizations l10n, DocumentStyleLoss loss) {
    switch (loss.kind) {
      case DocumentStyleLossKind.perLevelHeadingColor:
        final parts = (loss.detail ?? ':').split(':');
        return l10n
            .d(
              'Kopniveau {niveau} heeft een eigen kleur ({kleur}); de stijl kent één kopkleur.',
            )
            .replaceAll('{niveau}', parts.first)
            .replaceAll('{kleur}', parts.length > 1 ? parts[1] : '');
      case DocumentStyleLossKind.titlePageImage:
        return l10n.d(
          'Een afbeelding op alleen het titelblad; die is geen documentlogo.',
        );
      case DocumentStyleLossKind.centredLogo:
        return l10n.d(
          'Het logo stond gecentreerd; de stijl kent links en rechts, het komt links.',
        );
      case DocumentStyleLossKind.vectorOnlyLogo:
        return l10n.d(
          'Een afbeelding in de kop- of voettekst is alleen vectorbeeld (SVG) en kan geen logo worden.',
        );
    }
  }
}
