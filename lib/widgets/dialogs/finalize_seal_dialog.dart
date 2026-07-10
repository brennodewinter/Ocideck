import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/document_signature.dart';
import '../../theme/app_theme.dart';
import '../document_signature_view.dart';

/// Outcome of [FinalizeSealDialog]: confirming returns this (with an optional
/// [signature]); cancelling returns null.
class FinalizeSealResult {
  /// The collected visual signature, or null when the user sealed without one.
  final DocumentSignature? signature;

  const FinalizeSealResult({this.signature});
}

/// "Afronden & verzegelen": explains the one-way finalise + SHA-512 seal and
/// optionally collects a visual signature. Deliberately does NOT offer an
/// unfinalise — finalising is one-way in the UI.
class FinalizeSealDialog extends StatefulWidget {
  const FinalizeSealDialog({super.key});

  static Future<FinalizeSealResult?> show(BuildContext context) {
    return showDialog<FinalizeSealResult>(
      context: context,
      builder: (_) => const FinalizeSealDialog(),
    );
  }

  @override
  State<FinalizeSealDialog> createState() => _FinalizeSealDialogState();
}

class _FinalizeSealDialogState extends State<FinalizeSealDialog> {
  final _name = TextEditingController();
  final _role = TextEditingController();
  final _statement = TextEditingController();
  final _typed = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _statement.dispose();
    _typed.dispose();
    super.dispose();
  }

  String _today() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}';
  }

  DocumentSignature _currentSignature() => DocumentSignature(
    name: _name.text.trim(),
    role: _role.text.trim(),
    statement: _statement.text.trim(),
    typedSignature: _typed.text.trim(),
  );

  void _seal() {
    final base = _currentSignature();
    // The signing date is the seal date; fill it only when there is a signature.
    final signature = base.isEmpty ? null : base.copyWith(date: _today());
    Navigator.pop(context, FinalizeSealResult(signature: signature));
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
        title: Row(
          children: [
            const Icon(Icons.verified_user_outlined, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.d('Afronden & verzegelen'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(width: 460, child: _content(l10n)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton.icon(
            onPressed: _seal,
            icon: const Icon(Icons.lock_outline, size: 18),
            label: Text(l10n.d('Verzegelen')),
          ),
        ],
      ),
    );
  }

  Widget _content(AppLocalizations l10n) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d(
              'Rond deze presentatie af en bereken een SHA-512-zegel over de inhoud. Daarna is het bestand vergrendeld en niet meer te bewerken; latere wijzigingen worden zichtbaar. Dit kan in de app niet ongedaan worden gemaakt.',
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.d('Handtekening (optioneel)'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _field(l10n, _name, 'Naam'),
          const SizedBox(height: 10),
          _field(l10n, _role, 'Rol of functie'),
          const SizedBox(height: 10),
          _field(l10n, _statement, 'Verklaring', maxLines: 2),
          const SizedBox(height: 10),
          _field(l10n, _typed, 'Getypte handtekening'),
          const SizedBox(height: 16),
          _preview(l10n),
        ],
      ),
    );
  }

  Widget _field(
    AppLocalizations l10n,
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: l10n.d(label),
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _preview(AppLocalizations l10n) {
    final signature = _currentSignature();
    if (signature.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.slate400.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DocumentSignatureView(
        signature: signature.copyWith(date: _today()),
        compact: true,
      ),
    );
  }
}
