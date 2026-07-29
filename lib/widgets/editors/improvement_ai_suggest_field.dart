import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/ai_client_service.dart';
import '../../services/ai_security_gate.dart';
import '../../services/improvement_ai_service.dart';
import '../../state/improvement_ai_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';

/// Per-field AI suggest control for Procesverbetering slides (§9). Requires
/// both the AI and Procesverbetering modules; marks the field `ocideck_ai_assisted`.
class ImprovementAiSuggestField extends ConsumerStatefulWidget {
  const ImprovementAiSuggestField({
    super.key,
    required this.field,
    required this.fieldKey,
    required this.contextBuilder,
    required this.hasExistingText,
    required this.isAiDraft,
    required this.onSuggested,
    required this.onAccepted,
  });

  final ImprovementAiField field;
  final String fieldKey;
  final ImprovementAiContext Function() contextBuilder;
  final bool hasExistingText;
  final bool isAiDraft;
  final ValueChanged<String> onSuggested;
  final VoidCallback onAccepted;

  @override
  ConsumerState<ImprovementAiSuggestField> createState() =>
      _ImprovementAiSuggestFieldState();
}

class _ImprovementAiSuggestFieldState
    extends ConsumerState<ImprovementAiSuggestField> {
  bool _busy = false;

  bool get _aiAvailable => ref.watch(improvementAiAvailableProvider);

  Future<void> _suggest() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    void toast(String m) => messenger.showSnackBar(SnackBar(content: Text(m)));
    if (widget.hasExistingText) {
      final ok = await _confirmReplace(l10n);
      if (ok != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final client = await ref.read(improvementAiClientFactoryProvider)();
      final draft = await ImprovementAiService(client).suggest(
        field: widget.field,
        context: widget.contextBuilder(),
        languageName:
            AppLocalizations.languageNames[l10n.languageCode] ?? 'English',
      );
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
    } catch (e, s) {
      logError('ImprovementAiSuggestField._suggest', e, s);
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
    builder: (ctx) => AlertDialog(
      content: Text(
        l10n.d('Er staat al tekst. Vervangen door het AI-concept?'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.t('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.d('Vervangen')),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!_aiAvailable && !widget.isAiDraft) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Row(
        children: [
          if (_aiAvailable)
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
