part of '../app_shell.dart';

/// Vraag een URL op om een presentatie (pakket of markdown) op te halen.
Future<String?> _showUrlDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _UrlImportDialog(),
  );
}

class _UrlImportDialog extends StatefulWidget {
  const _UrlImportDialog();

  @override
  State<_UrlImportDialog> createState() => _UrlImportDialogState();
}

class _UrlImportDialogState extends State<_UrlImportDialog> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Herbouw bij elke wijziging zodat de Ophalen-knop live aan/uit gaat.
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Alleen een http(s)-URL met host is op te halen; alles daarbuiten laat
  /// de knop uit staan i.p.v. stil te falen na het klikken.
  bool get _isFetchable {
    final uri = Uri.tryParse(_controller.text.trim());
    if (uri == null || uri.host.isEmpty) return false;
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Openen via URL')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Plak de link naar een .md-bestand of een .ocideck-pakket; een .md opent als presentatie of document. De bron moet je browser toestaan het bestand te lezen.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate500),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: l10n.d('https://...'),
                prefixIcon: const Icon(Icons.link, size: 18),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (v) {
                if (_isFetchable) Navigator.pop(context, v);
              },
            ),
            // AC3 (#2826): de knop blijft niet alleen uit — de dialoog zegt
            // ook waarom, zodra er iets ingetikt is dat geen ophaalbaar
            // adres is. Een leeg veld blijft stil.
            if (_controller.text.trim().isNotEmpty && !_isFetchable) ...[
              const SizedBox(height: 8),
              Text(
                l10n.d(
                  'Voer een http(s)-adres met een servernaam in, bijvoorbeeld https://example.org/notities.md',
                ),
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.t('cancel')),
        ),
        ElevatedButton.icon(
          onPressed: _isFetchable
              ? () => Navigator.pop(context, _controller.text)
              : null,
          icon: const Icon(Icons.download, size: 16),
          label: Text(l10n.d('Ophalen')),
        ),
      ],
    );
  }
}
