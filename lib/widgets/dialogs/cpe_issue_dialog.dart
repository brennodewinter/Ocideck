import 'package:material_ui/material_ui.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import '../../l10n/app_localizations.dart';
import '../../services/cpe_certificate_service.dart';
import '../forms/form_fill_view.dart';
import '../forms/form_image_picker.dart';

/// One course, one participant table, an individual certificate for each row.
class CpeIssueDialog extends StatefulWidget {
  const CpeIssueDialog({
    super.key,
    required this.template,
    required this.language,
    this.projectPath,
  });
  final String template;
  final String language;
  final String? projectPath;

  @override
  State<CpeIssueDialog> createState() => _CpeIssueDialogState();
}

class _CpeIssueDialogState extends State<CpeIssueDialog> {
  late String _body = CpeCertificateService.groupForm(
    widget.template,
    widget.language,
  );
  String? _error;
  bool _busy = false;

  Future<void> _issue() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final opened = (FormFill.open(_body) as FormFillReady).fill;
      final paths = [
        for (final field in opened.spec.fields)
          for (final image in opened.answerOf(field.id).value.images)
            image.path,
      ];
      final support = formImageSupportFor(
        projectPath: widget.projectPath,
        dialogTitle: '',
      );
      final facts = await support?.probe(paths) ?? <String, FormImageFact>{};
      if (!mounted) return;
      final fill =
          (FormFill.open(_body, imageFacts: facts) as FormFillReady).fill;
      // Image facts are gathered by the fill view; the issuer checks the text
      // independently. Images remain optional and were checked on import.
      final certificates = CpeCertificateService.issue(
        widget.template,
        fill,
        widget.language,
      );
      Navigator.pop(context, certificates);
    } on FormatException catch (error) {
      setState(
        () => _error =
            '${context.l10n.d('Controleer de verplichte velden en de naam, het e-mailadres en de uren van elke deelnemer.')}${error.offset == null ? '' : ' (${context.l10n.d('Rij')} ${error.offset})'}',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('PE-bewijzen uitgeven')),
      content: SizedBox(
        width: 760,
        height: 600,
        child: Column(
          children: [
            Expanded(
              child: FormFillView(
                body: _body,
                images: formImageSupportFor(
                  projectPath: widget.projectPath,
                  dialogTitle: l10n.d('Kies een afbeelding'),
                ),
                onChanged: (body, _) => setState(() {
                  _body = body;
                  _error = null;
                }),
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
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
          onPressed: _busy ? null : _issue,
          child: Text(l10n.d('PE-bewijzen maken')),
        ),
      ],
    );
  }
}
