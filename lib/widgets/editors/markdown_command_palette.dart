import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';

enum MarkdownCommand {
  heading1,
  heading2,
  heading3,
  bulletList,
  numberedList,
  task,
  quote,
  link,
  image,
  table,
  codeBlock,
}

class _CommandItem {
  final MarkdownCommand command;
  final IconData icon;
  final String label;
  final String keywords;

  const _CommandItem(this.command, this.icon, this.label, this.keywords);
}

Future<MarkdownCommand?> showMarkdownCommandPalette(BuildContext context) {
  return showDialog<MarkdownCommand>(
    context: context,
    builder: (context) => const _MarkdownCommandDialog(),
  );
}

class _MarkdownCommandDialog extends StatefulWidget {
  const _MarkdownCommandDialog();

  @override
  State<_MarkdownCommandDialog> createState() => _MarkdownCommandDialogState();
}

class _MarkdownCommandDialogState extends State<_MarkdownCommandDialog> {
  String _query = '';

  List<_CommandItem> _items(AppLocalizations l10n) => [
    _CommandItem(
      MarkdownCommand.heading1,
      Icons.title,
      l10n.d('Kop 1'),
      'h1 titel heading',
    ),
    _CommandItem(
      MarkdownCommand.heading2,
      Icons.title,
      l10n.d('Kop 2'),
      'h2 titel heading',
    ),
    _CommandItem(
      MarkdownCommand.heading3,
      Icons.title,
      l10n.d('Kop 3'),
      'h3 titel heading',
    ),
    _CommandItem(
      MarkdownCommand.bulletList,
      Icons.format_list_bulleted,
      l10n.d('Opsomming'),
      'lijst bullets list',
    ),
    _CommandItem(
      MarkdownCommand.numberedList,
      Icons.format_list_numbered,
      l10n.d('Genummerde lijst'),
      'lijst numbers list',
    ),
    _CommandItem(
      MarkdownCommand.task,
      Icons.check_box_outlined,
      l10n.d('Taak'),
      'checkbox todo task',
    ),
    _CommandItem(
      MarkdownCommand.quote,
      Icons.format_quote,
      l10n.d('Citaat'),
      'quote blockquote',
    ),
    _CommandItem(
      MarkdownCommand.link,
      Icons.link,
      l10n.d('Link'),
      'url hyperlink',
    ),
    _CommandItem(
      MarkdownCommand.image,
      Icons.image_outlined,
      l10n.d('Afbeelding'),
      'image foto media',
    ),
    _CommandItem(
      MarkdownCommand.table,
      Icons.table_chart_outlined,
      l10n.d('Tabel'),
      'table kolommen',
    ),
    _CommandItem(
      MarkdownCommand.codeBlock,
      Icons.code,
      l10n.d('Codeblok'),
      'code fence',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final query = _query.trim().toLowerCase();
    final items = _items(l10n).where((item) {
      return query.isEmpty ||
          item.label.toLowerCase().contains(query) ||
          item.keywords.contains(query);
    }).toList();
    return AlertDialog(
      title: Text(l10n.d('Invoegen of opmaken')),
      content: SizedBox(
        width: 440,
        height: 430,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.d('Zoek een opdracht…'),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? Center(child: Text(l10n.d('Geen opdrachten gevonden')))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(item.icon, size: 20),
                          title: Text(item.label),
                          onTap: () => Navigator.pop(context, item.command),
                        );
                      },
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
      ],
    );
  }
}
