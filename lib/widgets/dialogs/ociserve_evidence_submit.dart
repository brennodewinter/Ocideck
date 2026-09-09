import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_evidence.dart';
import '../../state/ociserve_provider.dart';
import '../../utils/log.dart';

/// Het aanleverpad voor bewijs: vier stappen, met stap één al ingevuld.
///
/// 1. Soort — komt uit de eis waarop je klikte (al ingevuld).
/// 2. Bestand of foto — PNG, JPEG, WebP of PDF.
/// 3. Geldig tot — voorgevuld waar de soort dat weet, overslaanbaar.
/// 4. Toestemming — wat er met het document gebeurt, in gewone taal.
///
/// Ligt er al een geaccepteerd, geldig stuk? Dan toont het bewijsscherm
/// dat in plaats van deze knop.
class OciServeEvidenceSubmit extends ConsumerStatefulWidget {
  const OciServeEvidenceSubmit({
    super.key,
    required this.organizationId,
    required this.badgeTitle,
  });

  final String organizationId;
  final String badgeTitle;

  static Future<bool> show(
    BuildContext context, {
    required String organizationId,
    required String badgeTitle,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => OciServeEvidenceSubmit(
        organizationId: organizationId,
        badgeTitle: badgeTitle,
      ),
    );
    return result ?? false;
  }

  @override
  ConsumerState<OciServeEvidenceSubmit> createState() =>
      _OciServeEvidenceSubmitState();
}

class _OciServeEvidenceSubmitState
    extends ConsumerState<OciServeEvidenceSubmit> {
  int _step = 0;
  File? _file;
  Uint8List? _fileBytes;
  String? _fileError;
  DateTime? _validUntil;
  bool _submitting = false;
  String? _submitError;

  static const _allowedExtensions = ['png', 'jpg', 'jpeg', 'webp', 'pdf'];
  static const _allowedMime = {
    'image/png': 'image/png',
    'image/jpeg': 'image/jpeg',
    'image/webp': 'image/webp',
    'application/pdf': 'application/pdf',
  };

  String _detectMimeType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
      _ => 'application/octet-stream',
    };
  }

  Future<void> _pickFile() async {
    final l10n = context.l10n;
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedExtensions,
        dialogTitle: l10n.d('Bewijsstuk kiezen'),
      );
      if (picked.isEmpty) return;
      final file = picked.first;
      final bytes = await file.readAsBytes();
      final mimeType = _detectMimeType(file.name);
      if (!_allowedMime.containsKey(mimeType)) {
        setState(() => _fileError = 'unsupported_format');
        return;
      }
      setState(() {
        _file = File(file.path ?? '');
        _fileBytes = Uint8List.fromList(bytes);
        _fileError = null;
      });
    } catch (error, stack) {
      logError('OciServe: bestand kiezen', error.runtimeType, stack);
      setState(() => _fileError = 'pick_failed');
    }
  }

  Future<void> _submit() async {
    final bytes = _fileBytes;
    if (bytes == null || _file == null) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final notifier = ref.read(ociServeProvider.notifier);
      final mimeType = _detectMimeType(_file!.path.split('/').last);
      final hash = sha256.convert(bytes).toString();
      final slot = await notifier.requestEvidenceSlot(
        organizationId: widget.organizationId,
        request: EvidenceUploadRequest(
          filename: _file!.path.split('/').last,
          declaredType: mimeType,
          declaredSize: bytes.length,
          declaredHash: hash,
        ),
      );
      await notifier.uploadEvidenceContent(
        organizationId: widget.organizationId,
        evidenceId: slot.id,
        bytes: bytes,
        contentType: mimeType,
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error, stack) {
      logError('OciServe: bewijs aanleveren', error.runtimeType, stack);
      if (mounted) {
        setState(() {
          _submitting = false;
          _submitError = 'submit_failed';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.d('Bewijs aanleveren')),
      content: SizedBox(
        width: 480,
        child: Stepper(
          currentStep: _step,
          onStepContinue: () {
            if (_step < 3) {
              if (_step == 1 && _file == null) {
                setState(() => _fileError = 'no_file');
                return;
              }
              setState(() => _step++);
            } else {
              _submit();
            }
          },
          onStepCancel: () {
            if (_step > 0) {
              setState(() => _step--);
            } else {
              Navigator.pop(context, false);
            }
          },
          controlsBuilder: _stepControls,
          steps: [
            Step(
              title: Text(l10n.d('Soort')),
              content: _stepType(l10n, theme),
              isActive: _step >= 0,
              state: _step > 0 ? StepState.complete : StepState.indexed,
            ),
            Step(
              title: Text(l10n.d('Bestand')),
              content: _stepFile(l10n, theme),
              isActive: _step >= 1,
              state: _file != null && _step > 1
                  ? StepState.complete
                  : _step == 1
                  ? StepState.indexed
                  : StepState.disabled,
            ),
            Step(
              title: Text(l10n.d('Geldig tot')),
              content: _stepValidity(l10n, theme),
              isActive: _step >= 2,
              state: _step > 2 ? StepState.complete : StepState.indexed,
            ),
            Step(
              title: Text(l10n.d('Toestemming')),
              content: _stepConsent(l10n, theme),
              isActive: _step >= 3,
              state: _step == 3 ? StepState.indexed : StepState.disabled,
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepControls(
    BuildContext context,
    ControlsDetails details,
  ) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          FilledButton(
            onPressed: details.onStepContinue,
            child: Text(
              _step == 3
                  ? (_submitting
                      ? l10n.d('Bezig met versturen…')
                      : l10n.d('Aanleveren'))
                  : l10n.d('Volgende'),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: details.onStepCancel,
            child: Text(_step == 0 ? l10n.t('cancel') : l10n.d('Terug')),
          ),
        ],
      ),
    );
  }

  Widget _stepType(AppLocalizations l10n, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('U levert bewijs aan voor: {badge}').replaceAll(
            '{badge}',
            widget.badgeTitle,
          ),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Text(
          l10n.d(
            'Toegestane formaten: PNG, JPEG, WebP en PDF. '
            'SVG en actieve documentformaten worden geweigerd.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _stepFile(AppLocalizations l10n, ThemeData theme) {
    if (_fileError == 'no_file') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.d('Kies een bestand om aan te leveren.')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(l10n.d('Bestand kiezen')),
          ),
        ],
      );
    }
    if (_file == null) {
      return OutlinedButton.icon(
        onPressed: _pickFile,
        icon: const Icon(Icons.upload_file_outlined),
        label: Text(l10n.d('Bestand kiezen')),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _file!.path.endsWith('.pdf')
                  ? Icons.picture_as_pdf_outlined
                  : Icons.image_outlined,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _file!.path.split('/').last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: l10n.d('Ander bestand'),
              onPressed: _pickFile,
              icon: const Icon(Icons.swap_horiz),
            ),
          ],
        ),
        if (_fileBytes != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n
                  .d('{bytes} bytes')
                  .replaceAll('{bytes}', _fileBytes!.length.toString()),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
      ],
    );
  }

  Widget _stepValidity(AppLocalizations l10n, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.d('Tot wanneer is dit bewijs geldig?')),
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _validUntil ?? DateTime.now().add(
                    const Duration(days: 365 * 2),
                  ),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(
                    const Duration(days: 365 * 20),
                  ),
                );
                if (picked != null) setState(() => _validUntil = picked);
              },
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _validUntil != null
                    ? MaterialLocalizations.of(context)
                        .formatFullDate(_validUntil!)
                    : l10n.d('Datum kiezen'),
              ),
            ),
            if (_validUntil != null)
              TextButton(
                onPressed: () => setState(() => _validUntil = null),
                child: Text(l10n.d('Wissen')),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.d(
            'Laat leeg als het bewijs onbeperkt geldig is. '
            'We waarschuwen je voordat het verloopt.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _stepConsent(AppLocalizations l10n, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d(
            'U levert dit bewijsstuk aan ter beoordeling. '
            'Het wordt afgeschermd bewaard zolang het nodig is voor de badge. '
            'Een beoordelaar kijkt ernaar en stelt vast of het klopt.',
          ),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Text(
          l10n.d(
            'Uw bestand wordt gemarkeerd als "opgegeven, nog niet gecontroleerd" '
            'tot een beoordelaar het heeft bekeken.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        if (_submitError != null) ...[
          const SizedBox(height: 12),
          Text(
            l10n.d('Het aanleveren is mislukt. Probeer het opnieuw.'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}
