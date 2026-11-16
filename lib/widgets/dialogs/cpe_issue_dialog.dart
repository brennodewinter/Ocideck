import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/cpe_certificate_service.dart';
import '../../services/file_service.dart' show readStyleLogoBytes;
import '../../state/settings_provider.dart';
import '../../utils/bundled_asset.dart';
import '../forms/form_fill_view.dart';
import '../forms/form_image_picker.dart';
import '../forms/form_image_support.dart' show FormImagePreset;

/// One course, one participant table, an individual certificate for each row.
class CpeIssueDialog extends ConsumerStatefulWidget {
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
  ConsumerState<CpeIssueDialog> createState() => _CpeIssueDialogState();
}

class _CpeIssueDialogState extends ConsumerState<CpeIssueDialog> {
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

  /// De logo's van de stijlprofielen als klaargezette bronnen voor het
  /// logo-veld: de opleider heeft zijn huisstijl daar al staan, uploaden is
  /// dan niet meer nodig (#2923).
  Map<String, List<FormImagePreset>> _logoPresets() {
    final profiles = ref.read(settingsProvider).themeProfiles;
    return {
      'logo': [
        for (final profile in profiles)
          if (profile.effectiveDocumentLogoPath?.trim() case final path?
              when path.isNotEmpty)
            (label: profile.name, read: () => _logoBytes(path)),
      ],
    };
  }

  /// De bytes van een stijllogo: gebundeld via de assets, de rest via de
  /// vertrouwde lezer van stijlprofielen. Faalt hardop — de inname meldt de
  /// weigering dan in plaats van stil een leeg bestand neer te leggen.
  Future<Uint8List> _logoBytes(String path) async {
    if (isBundledAssetPath(path)) {
      final data = await rootBundle.load(bundledAssetKey(path));
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }
    final bytes = await readStyleLogoBytes(path);
    if (bytes == null) throw StateError('logo onleesbaar');
    return bytes;
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
                  presets: _logoPresets(),
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
