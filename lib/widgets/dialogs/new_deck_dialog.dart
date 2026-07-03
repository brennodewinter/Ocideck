import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/app_localizations.dart';
import '../../models/deck_template.dart';
import '../../theme/app_theme.dart';

/// The wizard's outcome: the deck title plus the chosen starting template.
class NewDeckChoice {
  final String title;
  final DeckTemplate template;

  const NewDeckChoice({required this.title, required this.template});
}

/// The new-presentation wizard: asks for a title and lets the user pick a
/// [DeckTemplate] whose example slides seed the fresh deck.
class NewDeckDialog extends StatefulWidget {
  const NewDeckDialog({super.key});

  static Future<NewDeckChoice?> show(BuildContext context) {
    return showDialog<NewDeckChoice>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const NewDeckDialog(),
    );
  }

  @override
  State<NewDeckDialog> createState() => _NewDeckDialogState();
}

/// Picker icons per [DeckTemplate.icon] key. Lives here (not in the model) so
/// the model layer stays Flutter-free, mirroring the slide-type registry.
const Map<String, IconData> _templateIcons = {
  'empty': Icons.crop_landscape_outlined,
  'briefing': Icons.summarize_outlined,
  'status': Icons.speed_outlined,
  'kickoff': Icons.rocket_launch_outlined,
  'communication': Icons.forum_outlined,
  'projectTimeline': Icons.timeline_outlined,
  'rasci': Icons.admin_panel_settings_outlined,
  'securityTasks': Icons.shield_outlined,
  'certification': Icons.verified_outlined,
  'training': Icons.school_outlined,
  'report': Icons.insert_chart_outlined,
  'research': Icons.travel_explore_outlined,
  'technical': Icons.code_outlined,
  'quiz': Icons.quiz_outlined,
};

class _NewDeckDialogState extends State<NewDeckDialog> {
  final _ctrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  DeckTemplate _template = deckTemplates.first;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: AlertDialog(
        title: Text(l10n.d('Nieuwe presentatie')),
        content: Form(
          key: _formKey,
          child: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _ctrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l10n.d('Titel'),
                    hintText: l10n.d('Bijv. Kwartaalupdate Q4'),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? l10n.d('Vul een titel in')
                      : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.d('Sjabloon'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                // Flexible met een plafond: op kleine vensters krimpt de
                // lijst mee in plaats van de dialoog te laten overlopen.
                Flexible(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 320),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.slate300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    // Reading-order tabbing through the tiles keeps the picker
                    // fully keyboard-operable (mirrors the slide-type dialog).
                    child: FocusTraversalGroup(
                      policy: ReadingOrderTraversalPolicy(),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: deckTemplates.length,
                        itemBuilder: (context, i) =>
                            _templateTile(deckTemplates[i]),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.t('cancel')),
          ),
          ElevatedButton(onPressed: _submit, child: Text(l10n.d('Aanmaken'))),
        ],
      ),
    );
  }

  Widget _templateTile(DeckTemplate template) {
    final l10n = context.l10n;
    final selected = template.id == _template.id;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: () => setState(() => _template = template),
        focusColor: AppTheme.accent.withValues(alpha: 0.14),
        hoverColor: AppTheme.accent.withValues(alpha: 0.06),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: selected ? AppTheme.accent.withValues(alpha: 0.10) : null,
          child: Row(
            children: [
              Icon(
                _templateIcons[template.icon] ?? Icons.crop_landscape_outlined,
                size: 22,
                color: AppTheme.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.d(template.title),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      l10n.d(template.description),
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ExcludeSemantics(
                child: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: selected ? AppTheme.accent : AppTheme.slate300,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(
        context,
        NewDeckChoice(title: _ctrl.text.trim(), template: _template),
      );
    }
  }
}
