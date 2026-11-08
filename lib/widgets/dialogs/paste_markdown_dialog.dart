import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// Dialoog "Markdown plakken" (#2825): een groot tekstvak voor Markdown uit
/// een andere toepassing (wiki, chat, AI-assistent), plus de knop die die
/// tekst opent. De dialoog is bewust dom: hij kent het openpad niet. [onOpen]
/// levert de tekst aan die poort — dezelfde veiligheidsscan en
/// Marp-routering als een `.md`-bestand — en geeft `null` terug als er een
/// tabblad opende; anders de kant-en-klare melding die in de dialoog blijft
/// staan, samen met de tekst, zodat de gebruiker die kan aanpassen.
class PasteMarkdownDialog extends StatefulWidget {
  const PasteMarkdownDialog({super.key, required this.onOpen});

  /// Open [text] als deck of document; `null` = gelukt (de dialoog sluit),
  /// anders de melding die in de dialoog getoond wordt. Wordt alleen
  /// aangeroepen met tekst die niet uit witruimte bestaat.
  final Future<String?> Function(String text) onOpen;

  static Future<void> show(
    BuildContext context, {
    required Future<String?> Function(String text) onOpen,
  }) {
    return showDialog<void>(
      context: context,
      // Geen barrier-tik: sluiten met tekst erin vraagt om bevestiging, en
      // die vraag hoort bij de knoppen — niet nog eens op een tweede plek.
      barrierDismissible: false,
      builder: (_) => PasteMarkdownDialog(onOpen: onOpen),
    );
  }

  @override
  State<PasteMarkdownDialog> createState() => _PasteMarkdownDialogState();
}

class _PasteMarkdownDialogState extends State<PasteMarkdownDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  /// Alleen witruimte telt als leeg: zowel voor de Open-knop als voor de
  /// vraag of annuleren om bevestiging moet vragen.
  bool get _hasText => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Herbouw bij elke wijziging: de Open-knop volgt "leeg" live mee en de
    // omvangsteller onder het veld loopt synchroon.
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _discard() async {
    if (_hasText) {
      final l10n = context.l10n;
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.d('Geplakte tekst verwerpen?')),
          content: Text(
            l10n.d('Er staat nog tekst in het veld; die wordt niet geopend.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.t('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: Text(l10n.d('Verwerpen')),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _open() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final failure = await widget.onOpen(_controller.text);
      if (!mounted) return;
      if (failure == null) {
        Navigator.of(context).pop();
        return;
      }
      // De tekst blijft bewust staan: een geweigerde of onleesbare tekst kan
      // de gebruiker corrigeren of alsnog ergens anders plakken (#2825 AC6).
      setState(() => _error = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Markdown plakken')),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Plak hier de Markdown-tekst. Met marp: true in de kopregels wordt het een presentatie, zonder wordt het een document.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate500),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 260,
              child: TextField(
                controller: _controller,
                autofocus: true,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                decoration: InputDecoration(
                  labelText: l10n.d('Markdown-tekst'),
                  alignLabelWithHint: true,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Karakters tellen is goedkoop en volstaat als omvangsindicatie;
            // de échte grens (UTF-8-bytes) toetst het openpad zelf, dat dan
            // óók meldt wat de limiet is.
            Text(
              l10n
                  .d('{n} tekens')
                  .replaceAll('{n}', '${_controller.text.length}'),
              style: TextStyle(fontSize: 11, color: AppTheme.slate500),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _discard,
          child: Text(l10n.t('cancel')),
        ),
        FilledButton.icon(
          onPressed: _busy || !_hasText ? null : _open,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.file_open_outlined, size: 16),
          label: Text(l10n.d('Openen in OciDeck')),
        ),
      ],
    );
  }
}
