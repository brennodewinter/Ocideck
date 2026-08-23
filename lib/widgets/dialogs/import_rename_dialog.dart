import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';

/// Vraag de gebruiker de titel te bevestigen of aan te passen ná een import.
///
/// Het geïmporteerde deck staat nog nergens op schijf — deze dialoog is het
/// moment waarop de gebruiker dat ziet (de melding zegt het expliciet) en de
/// naam kan bijsturen voordat het deck in een tabblad opent. Annuleren laat
/// de oorspronkelijke titel staan; het deck wordt daarna altijd als onopgeslagen
/// gemarkeerd, zodat de tab-stip en statusbalk tonen dat bewaren nog moet.
class ImportRenameDialog extends StatefulWidget {
  final String initialTitle;
  final int slideCount;

  const ImportRenameDialog({
    super.key,
    required this.initialTitle,
    required this.slideCount,
  });

  /// Geeft de bevestigde titel terug, of `null` bij annuleren (titel blijft
  /// ongewijzigd).
  static Future<String?> show(
    BuildContext context, {
    required String initialTitle,
    required int slideCount,
  }) => showDialog<String>(
    context: context,
    builder: (_) =>
        ImportRenameDialog(initialTitle: initialTitle, slideCount: slideCount),
  );

  @override
  State<ImportRenameDialog> createState() => _ImportRenameDialogState();
}

class _ImportRenameDialogState extends State<ImportRenameDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _ctrl.text.trim();
    Navigator.pop(context, value.isEmpty ? widget.initialTitle : value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _submit,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context, null),
      },
      child: AlertDialog(
        title: Text(l10n.d('Presentatie geïmporteerd.')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.slideCount} ${l10n.d('dia’s')}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.d(
                  'Bewaar de presentatie onder een eigen naam. Je kunt de titel nu aanpassen.',
                ),
                style: const TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.d('Titel'),
                  hintText: l10n.d('Bijv. Kwartaalupdate Q4'),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(onPressed: _submit, child: Text(l10n.d('Openen'))),
        ],
      ),
    );
  }
}
