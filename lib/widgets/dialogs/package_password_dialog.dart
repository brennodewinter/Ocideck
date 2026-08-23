import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// Vraagt het wachtwoord van een versleuteld `.ocideck`-pakket bij het openen.
/// Retourneert het ingevoerde wachtwoord, of `null` als de gebruiker afbreekt.
/// [retry] toont een "onjuist wachtwoord"-melding na een mislukte poging.
class PackagePasswordDialog extends StatefulWidget {
  final bool retry;

  const PackagePasswordDialog({super.key, this.retry = false});

  static Future<String?> show(BuildContext context, {bool retry = false}) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PackagePasswordDialog(retry: retry),
    );
  }

  @override
  State<PackagePasswordDialog> createState() => _PackagePasswordDialogState();
}

class _PackagePasswordDialogState extends State<PackagePasswordDialog> {
  final _ctrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_ctrl.text.isEmpty) return;
    Navigator.pop(context, _ctrl.text);
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
        title: Text(l10n.d('Versleuteld pakket')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.d(
                  'Dit pakket is met een wachtwoord beveiligd. Voer het wachtwoord in om het te openen.',
                ),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ctrl,
                autofocus: true,
                obscureText: _obscure,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: l10n.d('Wachtwoord'),
                  prefixIcon: const Icon(Icons.lock_outline, size: 18),
                  errorText: widget.retry
                      ? l10n.d('Onjuist wachtwoord. Probeer het opnieuw.')
                      : null,
                  suffixIcon: IconButton(
                    tooltip: _obscure
                        ? l10n.d('Wachtwoord tonen')
                        : l10n.d('Wachtwoord verbergen'),
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.t('cancel')),
          ),
          ElevatedButton(
            onPressed: _ctrl.text.isEmpty ? null : _submit,
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            child: Text(l10n.d('Ontgrendelen')),
          ),
        ],
      ),
    );
  }
}
