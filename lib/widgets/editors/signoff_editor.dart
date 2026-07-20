import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/document_signature.dart';
import '../../models/slide.dart';
import '../../state/deck_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_limits.dart' show cappedMemoryImage;
import '../dialogs/finalize_seal_dialog.dart';
import '../document_signature_view.dart';
import '../signature_draw_dialog.dart';
import '_editor_field.dart';

/// Editor for a `signOff` slide (PENTEST_MIAUW 1.6 / §8 A1): the report's
/// truthful-reporting attestation. It authors the **deck-level**
/// [DocumentSignature] (statement, rapporteur name/role, certification, typed
/// signature) — reused everywhere the sign-off is shown and covered by the seal —
/// via [DeckNotifier.setSignature], plus an optional slide heading. Sealing is
/// offered here through the shared [FinalizeSealDialog]; it is blocked while any
/// slide still carries unreviewed AI-drafted text (AI_ASSIST §16.3). Once the
/// deck is finalised the fields become read-only (the whole deck is locked).
class SignOffEditor extends ConsumerStatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final bool nestedInScrollView;

  const SignOffEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.nestedInScrollView = false,
  });

  @override
  ConsumerState<SignOffEditor> createState() => _SignOffEditorState();
}

class _SignOffEditorState extends ConsumerState<SignOffEditor>
    with EditorTextControllers {
  late final TextEditingController _title;
  late final TextEditingController _statement;
  late final TextEditingController _name;
  late final TextEditingController _role;
  late final TextEditingController _certification;
  late final TextEditingController _typed;

  /// The signing date is set at seal time; preserved across edits so a re-seal
  /// keeps it.
  String _date = '';

  /// The drawn signature as an embedded `data:` image URI, preserved across
  /// edits (the text fields don't carry it).
  String _imagePath = '';

  @override
  void initState() {
    super.initState();
    final sig =
        ref.read(deckProvider).deck?.signature ?? const DocumentSignature();
    _date = sig.date;
    _imagePath = sig.imagePath;
    _title = newController(widget.slide.title, _emitTitle);
    _statement = newController(sig.statement, _emitSignature);
    _name = newController(sig.name, _emitSignature);
    _role = newController(sig.role, _emitSignature);
    _certification = newController(sig.certification, _emitSignature);
    _typed = newController(sig.typedSignature, _emitSignature);
  }

  void _emitTitle() {
    widget.onUpdate(widget.slide.copyWith(title: _title.text.trim()));
  }

  void _emitSignature() {
    ref
        .read(deckProvider.notifier)
        .setSignature(
          DocumentSignature(
            name: _name.text.trim(),
            role: _role.text.trim(),
            certification: _certification.text.trim(),
            statement: _statement.text.trim(),
            typedSignature: _typed.text.trim(),
            imagePath: _imagePath,
            date: _date,
          ),
        );
  }

  Future<void> _drawSignature() async {
    final uri = await SignatureDrawDialog.show(context);
    if (uri == null || !mounted) return;
    setState(() => _imagePath = uri);
    _emitSignature();
  }

  void _clearDrawnSignature() {
    setState(() => _imagePath = '');
    _emitSignature();
  }

  /// The freehand-signature control: a "draw" button, and — once something is
  /// drawn — a preview of it plus a redraw/clear row. The drawn image takes
  /// precedence over the typed signature wherever the sign-off is rendered.
  Widget _drawnSignatureField(AppLocalizations l10n) {
    final bytes = decodeEmbeddedSignatureImage(_imagePath);
    if (bytes == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _drawSignature,
          icon: const Icon(Icons.gesture, size: 16),
          label: Text(l10n.d('Handtekening tekenen')),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          height: 72,
          padding: const EdgeInsets.all(6),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: AppTheme.slate50,
            border: Border.all(color: AppTheme.slate300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Image(image: cappedMemoryImage(bytes), fit: BoxFit.contain),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _drawSignature,
              icon: const Icon(Icons.gesture, size: 16),
              label: Text(l10n.d('Handtekening tekenen')),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _clearDrawnSignature,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: Text(l10n.d('Wissen')),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _finalizeAndSeal() async {
    final notifier = ref.read(deckProvider.notifier);
    final blocking = notifier.slidesBlockingSeal;
    final l10n = context.l10n;
    if (blocking.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${l10n.d('Verzegelen kan pas als alle AI-concepten zijn nagekeken. Nog te controleren op dia:')} ${blocking.join(', ')}',
          ),
        ),
      );
      return;
    }
    final initial =
        ref.read(deckProvider).deck?.signature ?? const DocumentSignature();
    final result = await FinalizeSealDialog.show(
      context,
      initial: initial,
      standardsUsed: ref.read(deckProvider).deck?.standardsUsed ?? const [],
    );
    if (result == null || !mounted) return;
    notifier.finalizeAndSeal(signature: result.signature);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.d('Verzegeld. Sla op (Ctrl/Cmd+S) om te bewaren.'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final deck = ref.watch(deckProvider.select((s) => s.deck));
    final finalized = deck?.finalized ?? false;

    if (finalized) {
      return editorScrollList(
        nestedInScrollView: widget.nestedInScrollView,
        children: [_sealedNotice(context, deck?.sealAt ?? '')],
      );
    }

    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        EditorField(label: 'Titel', controller: _title, hint: 'Ondertekening'),
        const SizedBox(height: 16),
        const SectionLabel('Waarheidsverklaring'),
        EditorField(
          label: 'Verklaring',
          controller: _statement,
          hint: 'Deze rapportage is naar waarheid opgesteld.',
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        const SectionLabel('Rapporteur'),
        EditorField(label: 'Naam', controller: _name),
        const SizedBox(height: 12),
        EditorField(label: 'Rol of functie', controller: _role),
        const SizedBox(height: 12),
        EditorField(label: 'Certificering', controller: _certification),
        const SizedBox(height: 12),
        EditorField(label: 'Getypte handtekening', controller: _typed),
        const SizedBox(height: 12),
        _drawnSignatureField(l10n),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _finalizeAndSeal,
            icon: const Icon(Icons.lock_outline, size: 16),
            label: Text(l10n.d('Afronden & verzegelen')),
          ),
        ),
      ],
    );
  }

  Widget _sealedNotice(BuildContext context, String sealedAt) {
    final l10n = context.l10n;
    // A finalised deck always carries a seal timestamp; show its date.
    final date = sealedAt.isEmpty ? '' : sealedAt.split('T').first;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.slate300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user, size: 18, color: AppTheme.scopeTested),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${l10n.d('Verzegeld op')} $date',
              style: TextStyle(fontSize: 13, color: AppTheme.slate700),
            ),
          ),
        ],
      ),
    );
  }
}
