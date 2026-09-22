import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/slide.dart';
import '../../services/ai_client_service.dart';
import '../../services/ai_condense_service.dart';
import '../../services/ai_security_gate.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';
import '../editors/list_style_selector.dart';

/// De keuzedialoog achter "Vat samen met AI…" in de teksteditor van een
/// vrije-tekstdia. De auteur kiest een korte samenvatting of kernpunten
/// (met lijststijl), bekijkt het concept en past het toe — of niet.
/// De volledige brontekst verhuist daarbij naar de speakernotities.
///
/// [generate] levert het AI-verzoek; de dialoog zelf weet niets van de client,
/// zodat tests hem met een nep-generator kunnen voeden.
Future<AiCondenseResult?> showAiCondenseDialog(
  BuildContext context, {
  required Future<AiCondenseResult?> Function(AiCondenseMode, ListStyle)
  generate,
}) => showDialog<AiCondenseResult>(
  context: context,
  builder: (_) => AiCondenseDialog(generate: generate),
);

class AiCondenseDialog extends StatefulWidget {
  const AiCondenseDialog({super.key, required this.generate});

  final Future<AiCondenseResult?> Function(AiCondenseMode, ListStyle) generate;

  @override
  State<AiCondenseDialog> createState() => _AiCondenseDialogState();
}

class _AiCondenseDialogState extends State<AiCondenseDialog> {
  AiCondenseMode _mode = AiCondenseMode.summary;
  ListStyle _style = ListStyle.bullets;
  bool _busy = false;
  String? _error;
  AiCondenseResult? _result;

  Future<void> _generate() async {
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.generate(_mode, _style);
      if (!mounted) return;
      if (result == null) {
        _error = l10n.d('Het model gaf geen tekst terug.');
      } else {
        _result = result;
      }
    } on AiGateException {
      _error = l10n.d(
        'AI-assistentie is niet beschikbaar. Controleer de instellingen.',
      );
    } on AiRequestException {
      _error = l10n.d(
        'De AI-aanroep is mislukt (model niet geladen of server onbereikbaar).',
      );
    } catch (error, stackTrace) {
      logError('AiCondenseDialog._generate', error, stackTrace);
      _error = l10n.d(
        'De AI-aanroep is mislukt (model niet geladen of server onbereikbaar).',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Tekst inkorten met AI')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'De volledige tekst verhuist naar de speakernotities — er gaat niets verloren.',
              ),
              style: TextStyle(fontSize: 12.5, color: AppTheme.slate600),
            ),
            const SizedBox(height: 8),
            RadioGroup<AiCondenseMode>(
              groupValue: _mode,
              onChanged: _busy
                  ? (_) {}
                  : (v) => setState(() {
                      _mode = v!;
                      _result = null;
                    }),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _modeTile(
                    AiCondenseMode.summary,
                    l10n.d('Korte samenvatting'),
                    l10n.d('Eén alinea die op één dia past.'),
                  ),
                  _modeTile(
                    AiCondenseMode.keyPoints,
                    l10n.d('Kernpunten (max. 8)'),
                    l10n.d('Een compacte lijst met de hoofdpunten.'),
                  ),
                ],
              ),
            ),
            if (_mode == AiCondenseMode.keyPoints)
              Padding(
                padding: const EdgeInsets.only(left: 48, top: 4),
                child: ListStyleSelector(
                  value: _style,
                  allowRichText: false,
                  onChanged: (value) => setState(() {
                    _style = value;
                    // De punten zijn stijlonafhankelijk — een gewijzigde
                    // stijl volgt in preview én resultaat zonder opnieuw
                    // te genereren.
                    final result = _result;
                    if (result != null &&
                        result.mode == AiCondenseMode.keyPoints) {
                      _result = AiCondenseResult(
                        mode: result.mode,
                        listStyle: value,
                        points: result.points,
                      );
                    }
                  }),
                ),
              ),
            if (_result != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(child: _preview(_result!)),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(fontSize: 12, color: AppTheme.dangerFg),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l10n.t('cancel')),
        ),
        if (_result != null)
          TextButton(
            onPressed: _busy ? null : _generate,
            child: Text(l10n.d('Opnieuw')),
          ),
        if (_result == null)
          FilledButton(
            onPressed: _busy ? null : _generate,
            child: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.d('Genereer')),
          )
        else
          FilledButton(
            onPressed: () => Navigator.pop(context, _result),
            child: Text(l10n.d('Toepassen')),
          ),
      ],
    );
  }

  Widget _modeTile(AiCondenseMode mode, String title, String subtitle) {
    return RadioListTile<AiCondenseMode>(
      value: mode,
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title, style: const TextStyle(fontSize: 13)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11.5)),
    );
  }

  /// Het concept zoals het straks op de dia staat: een alinea, of de punten
  /// met het marker dat bij de gekozen lijststijl hoort.
  Widget _preview(AiCondenseResult result) {
    if (result.mode == AiCondenseMode.summary) {
      return SelectableText(
        result.summary,
        style: const TextStyle(fontSize: 13, height: 1.4),
      );
    }
    return SelectableText(
      [
        for (var i = 0; i < result.points.length; i++)
          switch (result.listStyle) {
            ListStyle.numbered => '${i + 1}. ${result.points[i]}',
            ListStyle.checklist => '☐ ${result.points[i]}',
            _ => '• ${result.points[i]}',
          },
      ].join('\n'),
      style: const TextStyle(fontSize: 13, height: 1.5),
    );
  }
}
