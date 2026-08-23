import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../services/ai_client_service.dart';
import '../../services/ai_security_gate.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';

/// Gedeelde bediening voor AI-tekstvoorstellen.
///
/// De aanroeper blijft verantwoordelijk voor de domeinspecifieke service; deze
/// widget beheert uitsluitend de bevestiging, voortgang en herkomstmarkering.
class AiSuggestControl extends StatefulWidget {
  const AiSuggestControl({
    super.key,
    required this.isAvailable,
    required this.hasExistingText,
    required this.isAiDraft,
    required this.loadSuggestion,
    required this.onSuggested,
    required this.onAccepted,
    this.padding = const EdgeInsets.only(top: 4, bottom: 8),
  });

  final bool isAvailable;
  final bool hasExistingText;
  final bool isAiDraft;
  final Future<String> Function() loadSuggestion;
  final ValueChanged<String> onSuggested;
  final VoidCallback onAccepted;
  final EdgeInsetsGeometry padding;

  @override
  State<AiSuggestControl> createState() => _AiSuggestControlState();
}

class _AiSuggestControlState extends State<AiSuggestControl> {
  bool _busy = false;

  Future<void> _suggest() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    void toast(String message) =>
        messenger.showSnackBar(SnackBar(content: Text(message)));

    if (widget.hasExistingText) {
      final replace = await _confirmReplace(l10n);
      if (replace != true || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      final draft = await widget.loadSuggestion();
      if (!mounted) return;
      if (draft.isEmpty) {
        toast(l10n.d('Het model gaf geen tekst terug.'));
        return;
      }
      widget.onSuggested(draft);
    } on AiGateException {
      toast(
        l10n.d(
          'AI-assistentie is niet beschikbaar. Controleer de instellingen.',
        ),
      );
    } on AiRequestException {
      toast(
        l10n.d(
          'De AI-aanroep is mislukt (model niet geladen of server onbereikbaar).',
        ),
      );
    } catch (error, stackTrace) {
      logError('AiSuggestControl._suggest', error, stackTrace);
      toast(
        l10n.d(
          'De AI-aanroep is mislukt (model niet geladen of server onbereikbaar).',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmReplace(AppLocalizations l10n) => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      content: Text(
        l10n.d('Er staat al tekst. Vervangen door het AI-concept?'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.t('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l10n.d('Vervangen')),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!widget.isAvailable && !widget.isAiDraft) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: widget.padding,
      child: Row(
        children: [
          if (widget.isAvailable)
            TextButton.icon(
              onPressed: _busy ? null : _suggest,
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_outlined, size: 16),
              label: Text(
                _busy
                    ? l10n.d('Bezig met AI-analyse…')
                    : l10n.d('Tekst voorstellen (AI)'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          if (widget.isAiDraft) ...[
            const SizedBox(width: 8),
            _aiBadge(l10n),
            const SizedBox(width: 4),
            TextButton(
              onPressed: widget.onAccepted,
              child: Text(
                l10n.d('Nagekeken'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _aiBadge(AppLocalizations l10n) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppTheme.amber500.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.auto_awesome, size: 12, color: AppTheme.amber700),
        const SizedBox(width: 4),
        Text(
          l10n.d('AI-concept'),
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.amber700,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
