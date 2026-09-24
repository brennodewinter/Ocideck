import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../services/ai_client_service.dart';
import '../../services/ai_security_gate.dart';
import '../../services/ai_translate_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';
import '../searchable_language_picker.dart';

/// De keuzedialoog achter "Vertaal met AI…" in het ⋮-menu en het
/// commandopalet. De auteur kiest de doeltaal; de dialoog vertaalt dia voor
/// dia met zichtbare voortgang en annuleren, en levert het vertaalde deck als
/// [DeckTranslationResult] terug aan de aanroeper — die opent het als kopie
/// in een nieuw tabblad.
///
/// [translate] levert het AI-verzoek; de dialoog zelf weet niets van de
/// client, zodat tests hem met een nep-vertaler kunnen voeden.
Future<DeckTranslationResult?> showAiTranslateDialog(
  BuildContext context, {
  required String initialLanguageCode,
  required Future<DeckTranslationResult?> Function(
    String languageCode,
    String languageName,
    void Function(int done, int total) onProgress,
    bool Function() isCancelled,
  )
  translate,
}) => showDialog<DeckTranslationResult>(
  context: context,
  builder: (_) => AiTranslateDialog(
    initialLanguageCode: initialLanguageCode,
    translate: translate,
  ),
);

class AiTranslateDialog extends StatefulWidget {
  const AiTranslateDialog({
    super.key,
    required this.initialLanguageCode,
    required this.translate,
  });

  final String initialLanguageCode;
  final Future<DeckTranslationResult?> Function(
    String languageCode,
    String languageName,
    void Function(int done, int total) onProgress,
    bool Function() isCancelled,
  )
  translate;

  @override
  State<AiTranslateDialog> createState() => _AiTranslateDialogState();
}

class _AiTranslateDialogState extends State<AiTranslateDialog> {
  late String _languageCode = widget.initialLanguageCode;
  bool _busy = false;
  bool _cancelled = false;
  int _done = 0;
  int _total = 0;
  String? _error;

  Future<void> _run() async {
    final l10n = context.l10n;
    final languageName =
        AppLocalizations.languageNames[_languageCode] ?? _languageCode;
    setState(() {
      _busy = true;
      _cancelled = false;
      _error = null;
      _done = 0;
    });
    try {
      final result = await widget.translate(_languageCode, languageName, (
        done,
        total,
      ) {
        if (mounted) {
          setState(() {
            _done = done;
            _total = total;
          });
        }
      }, () => _cancelled);
      if (!mounted) return;
      if (result == null) {
        // Geannuleerd: terug naar de keuzestap, geen fout.
        setState(() => _busy = false);
        return;
      }
      Navigator.pop(context, result);
    } on AiGateException {
      setState(() {
        _busy = false;
        _error = l10n.d(
          'AI-assistentie is niet beschikbaar. Controleer de instellingen.',
        );
      });
    } on AiRequestException {
      setState(() {
        _busy = false;
        _error = l10n.d(
          'De AI-aanroep is mislukt (model niet geladen of server onbereikbaar).',
        );
      });
    } catch (error, stackTrace) {
      logError('AiTranslateDialog._run', error, stackTrace);
      setState(() {
        _busy = false;
        _error = l10n.d(
          'De AI-aanroep is mislukt (model niet geladen of server onbereikbaar).',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Vertaal met AI')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Alle zichtbare teksten en speakernotities worden vertaald. De vertaling opent als kopie in een nieuw tabblad — het origineel blijft ongewijzigd.',
              ),
              style: TextStyle(fontSize: 12.5, color: AppTheme.slate600),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.d(
                'Controleer de vertaling voordat je hem gebruikt: AI-vertalingen zijn concepten.',
              ),
              style: TextStyle(fontSize: 12.5, color: AppTheme.slate600),
            ),
            const SizedBox(height: 12),
            SearchableLanguagePicker(
              languageCode: _languageCode,
              labelText: l10n.d('Doeltaal'),
              width: double.infinity,
              onLanguageChanged: _busy
                  ? (_) {}
                  : (code) => setState(() => _languageCode = code),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _total > 0 ? _done / _total : null,
              ),
              const SizedBox(height: 6),
              Text(
                '${l10n.d('Dia')} $_done / $_total',
                style: const TextStyle(fontSize: 12),
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
          onPressed: _busy
              ? () => setState(() => _cancelled = true)
              : () => Navigator.pop(context),
          child: Text(l10n.t('cancel')),
        ),
        if (!_busy)
          FilledButton(onPressed: _run, child: Text(l10n.d('Vertalen'))),
      ],
    );
  }
}
