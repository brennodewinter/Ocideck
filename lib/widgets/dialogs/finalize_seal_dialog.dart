import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/document_signature.dart';
import '../../services/reference_standards.dart';
import '../../theme/app_theme.dart';
import '../document_signature_view.dart';
import '../signature_draw_dialog.dart';

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
  /// Pre-fills the signature fields (e.g. from the deck's existing
  /// [DocumentSignature] authored on a sign-off slide). Null = start blank.
  final DocumentSignature? initial;

  /// De standaarden die het deck vastlegt (`naam@versie`, EIS 4.3.2). Wordt
  /// hier alleen gebruikt om te melden dat er inmiddels een nieuwere versie van
  /// zo'n standaard bestaat.
  final List<String> standardsUsed;

  const FinalizeSealDialog({
    super.key,
    this.initial,
    this.standardsUsed = const [],
  });

  static Future<FinalizeSealResult?> show(
    BuildContext context, {
    DocumentSignature? initial,
    List<String> standardsUsed = const [],
  }) {
    return showDialog<FinalizeSealResult>(
      context: context,
      builder: (_) =>
          FinalizeSealDialog(initial: initial, standardsUsed: standardsUsed),
    );
  }

  @override
  State<FinalizeSealDialog> createState() => _FinalizeSealDialogState();
}

class _FinalizeSealDialogState extends State<FinalizeSealDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _role = TextEditingController(text: widget.initial?.role ?? '');
  late final _certification = TextEditingController(
    text: widget.initial?.certification ?? '',
  );
  late final _statement = TextEditingController(
    text: widget.initial?.statement ?? '',
  );
  late final _typed = TextEditingController(
    text: widget.initial?.typedSignature ?? '',
  );

  /// The drawn signature as an embedded `data:` image URI, preserved so sealing
  /// keeps a signature drawn on the sign-off slide.
  late String _imagePath = widget.initial?.imagePath ?? '';

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _certification.dispose();
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
    certification: _certification.text.trim(),
    statement: _statement.text.trim(),
    typedSignature: _typed.text.trim(),
    imagePath: _imagePath,
  );

  Future<void> _drawSignature() async {
    final uri = await SignatureDrawDialog.show(context);
    if (uri == null || !mounted) return;
    setState(() => _imagePath = uri);
  }

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
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [_staleStandardsNotice(l10n), _content(l10n)],
          ),
        ),
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
          _field(l10n, _certification, 'Certificering'),
          const SizedBox(height: 10),
          _field(l10n, _statement, 'Verklaring', maxLines: 2),
          const SizedBox(height: 10),
          _field(l10n, _typed, 'Getypte handtekening'),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _drawSignature,
                icon: const Icon(Icons.gesture, size: 16),
                label: Text(l10n.d('Handtekening tekenen')),
              ),
              if (_imagePath.startsWith('data:')) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => setState(() => _imagePath = ''),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text(l10n.d('Wissen')),
                ),
              ],
            ],
          ),
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

  /// Meldt dat een standaard waartegen is getoetst inmiddels is bijgewerkt.
  ///
  /// Verzegelen is het moment waarop het rapport vast komt te liggen, dus het
  /// is ook het laatste moment waarop dit nog uitmaakt. Bewust een melding en
  /// geen blokkade: tegen een oudere versie toetsen is volstrekt legitiem — de
  /// pentest is nu eenmaal uitgevoerd toen die versie gold — het moet alleen
  /// een bewuste vaststelling zijn en geen verrassing achteraf.
  ///
  /// Vergelijkt wat het deck vastlegde met wat deze build meedraagt; geen
  /// netwerk, want dat zou hier ongevraagd verkeer zijn.
  Widget _staleStandardsNotice(AppLocalizations l10n) {
    final stale = outdatedStandards(widget.standardsUsed);
    if (stale.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.amber600.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d(
              'Er is inmiddels een nieuwere versie van een standaard waartegen is getoetst:',
            ),
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          for (final s in stale)
            Text(
              '${s.name}: ${l10n.d('vastgelegd')} ${s.recorded} · '
              '${l10n.d('nu beschikbaar')} ${s.current}',
              style: const TextStyle(fontSize: 11.5),
            ),
          const SizedBox(height: 4),
          Text(
            l10n.d(
              'Dat hoeft niet fout te zijn — het onderzoek is uitgevoerd toen die versie gold. Het rapport legt vast wat er echt is gebruikt.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate600),
          ),
        ],
      ),
    );
  }
}
