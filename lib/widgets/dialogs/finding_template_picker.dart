import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/finding_template.dart';
import '../../services/finding_template_library.dart';
import '../../theme/app_theme.dart';

/// A searchable picker over the reusable finding-template library
/// (PENTEST_MIAUW §17). Returns the chosen [FindingTemplate] (or null on
/// cancel); the caller pulls it into the current finding and specialises it.
class FindingTemplatePicker extends StatefulWidget {
  const FindingTemplatePicker({super.key});

  static Future<FindingTemplate?> show(BuildContext context) =>
      showDialog<FindingTemplate>(
        context: context,
        builder: (_) => const FindingTemplatePicker(),
      );

  @override
  State<FindingTemplatePicker> createState() => _FindingTemplatePickerState();
}

class _FindingTemplatePickerState extends State<FindingTemplatePicker> {
  final _search = TextEditingController();
  final _library = FindingTemplateLibrary.instance;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final matches = _library.search(_search.text);
    return AlertDialog(
      title: Text(l10n.d('Sjabloon kiezen')),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: l10n.d('Zoek een sjabloon'),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: matches.isEmpty
                  ? Center(child: Text(l10n.d('Geen sjablonen gevonden')))
                  : ListView.separated(
                      itemCount: matches.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) => _tile(context, matches[i]),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Annuleren')),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, FindingTemplate template) {
    final subtitleParts = [
      if (template.severity.isNotEmpty) template.severity,
      if (template.cweId != null) 'CWE-${template.cweId}',
    ];
    return ListTile(
      title: Text(template.title),
      subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' · ')),
      trailing: Icon(Icons.chevron_right, color: AppTheme.slate400),
      onTap: () => Navigator.of(context).pop(template),
    );
  }
}
