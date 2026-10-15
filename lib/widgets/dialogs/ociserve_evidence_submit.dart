import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_evidence.dart';
import '../../models/ociserve_evidence_item.dart';
import '../../state/ociserve_provider.dart';
import '../../utils/log.dart';
import '../../utils/content_hash.dart';

/// Het aanleverpad voor bewijs: vier stappen.
///
/// 1. Soort — een van de gepubliceerde bewijssoorten van de organisatie.
/// 2. Bestand of foto — PNG, JPEG, WebP of PDF.
/// 3. Geldig tot — meegestuurd als opgegeven einddatum, overslaanbaar.
/// 4. Toestemming — wat er met het document gebeurt, in gewone taal.
///
/// Aanleveren is drie stappen op de server: een bestandsslot, de bytes, en na
/// de controle het bewijsstuk zelf. Alleen dat laatste komt in de wachtrij van
/// een beoordelaar; een losse upload doet dat niet.
///
/// Ligt er al een geaccepteerd, geldig stuk? Dan toont het bewijsscherm
/// dat in plaats van deze knop.
class OciServeEvidenceSubmit extends ConsumerStatefulWidget {
  const OciServeEvidenceSubmit({
    super.key,
    required this.organizationId,
    required this.participantId,
    required this.badgeTitle,
    this.pollInterval = const Duration(milliseconds: 1500),
    this.maxPolls = 20,
    this.pickFile,
  });

  final String organizationId;
  final String participantId;
  final String badgeTitle;

  /// Hoe lang en hoe vaak we op de controle van de upload wachten voordat we
  /// de cursist vragen het later te proberen.
  final Duration pollInterval;
  final int maxPolls;

  /// Vervangt de bestandskiezer van het besturingssysteem; bedoeld voor tests.
  final Future<({String name, Uint8List bytes})?> Function()? pickFile;

  static Future<bool> show(
    BuildContext context, {
    required String organizationId,
    required String participantId,
    required String badgeTitle,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => OciServeEvidenceSubmit(
        organizationId: organizationId,
        participantId: participantId,
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
  String _fileName = '';
  Uint8List? _fileBytes;
  String? _fileError;
  DateTime? _validUntil;
  bool _submitting = false;
  String? _submitError;
  List<OciServeEvidenceType>? _types;
  bool _typesFailed = false;
  String? _typeId;
  bool _typeMissing = false;

  /// Een herhaalde poging gebruikt hetzelfde bestandsslot en dezelfde sleutel,
  /// zodat een netwerkfout geen tweede upload of tweede bewijsstuk maakt. Het
  /// slot telt pas mee als de bytes erin staan.
  String? _slotId;
  final String _itemKey = const Uuid().v4();

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    try {
      final types = await ref
          .read(ociServeProvider.notifier)
          .evidenceTypes(widget.organizationId);
      if (!mounted) return;
      setState(() => _types = types);
    } catch (error, stack) {
      logError('OciServe: bewijssoorten laden', error.runtimeType, stack);
      if (mounted) setState(() => _typesFailed = true);
    }
  }

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
      final custom = widget.pickFile;
      final ({String name, Uint8List bytes}) file;
      if (custom != null) {
        final chosen = await custom();
        if (chosen == null) return;
        file = chosen;
      } else {
        final picked = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: _allowedExtensions,
          dialogTitle: l10n.d('Bewijsstuk kiezen'),
        );
        if (picked.isEmpty) return;
        file = (
          name: picked.first.name,
          bytes: await picked.first.readAsBytes(),
        );
      }
      final bytes = file.bytes;
      final mimeType = _detectMimeType(file.name);
      if (!_allowedMime.containsKey(mimeType)) {
        setState(() => _fileError = 'unsupported_format');
        return;
      }
      setState(() {
        _fileName = file.name;
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
    final typeId = _typeId;
    if (bytes == null || _fileName.isEmpty || typeId == null) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final notifier = ref.read(ociServeProvider.notifier);
      var slotId = _slotId;
      if (slotId == null) {
        final mimeType = _detectMimeType(_fileName);
        // Het slot hangt aan de cursist zelf: zonder deelnemer blijft de upload
        // los van het dossier en toont "Mijn bewijs" het bewijsstuk niet.
        final slot = await notifier.requestEvidenceSlot(
          organizationId: widget.organizationId,
          request: EvidenceUploadRequest(
            filename: _fileName,
            declaredType: mimeType,
            declaredSize: bytes.length,
            declaredHash: sha256Hex(bytes),
            participantId: widget.participantId,
          ),
        );
        slotId = slot.id;
        await notifier.uploadEvidenceContent(
          organizationId: widget.organizationId,
          evidenceId: slotId,
          bytes: bytes,
          contentType: mimeType,
        );
        // Pas nu is het slot te hergebruiken. Faalt de upload, dan blijft het
        // slot leeg en wijst een nieuwe poging op een slot dat nooit vol komt.
        _slotId = slotId;
      }
      final upload = await _awaitVerification(notifier, slotId);
      if (!mounted) return;
      if (upload == null) {
        setState(() {
          _submitting = false;
          _submitError = 'checking';
        });
        return;
      }
      if (!upload.isClean) {
        // Een geweigerd slot is niet te hergebruiken: de volgende poging begint opnieuw.
        setState(() {
          _slotId = null;
          _submitting = false;
          _submitError = 'rejected';
        });
        return;
      }
      await notifier.createEvidenceItem(
        organizationId: widget.organizationId,
        participantId: widget.participantId,
        evidenceTypeId: typeId,
        uploadId: slotId,
        idempotencyKey: _itemKey,
        declaredValidUntil: _validUntil,
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

  /// Wacht tot de server de upload heeft gecontroleerd. `null`: nog niet klaar
  /// binnen de wachttijd; de cursist probeert het later en hergebruikt het slot.
  Future<EvidenceUpload?> _awaitVerification(
    OciServeNotifier notifier,
    String slotId,
  ) async {
    for (var poll = 0; poll < widget.maxPolls; poll++) {
      final upload = await notifier.evidenceDetail(
        organizationId: widget.organizationId,
        evidenceId: slotId,
      );
      if (!upload.isInProgress) return upload;
      await Future<void>.delayed(widget.pollInterval);
      if (!mounted) return null;
    }
    return null;
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
            if (_submitting) return;
            if (_step < 3) {
              if (_step == 0 && _typeId == null) {
                setState(() => _typeMissing = true);
                return;
              }
              if (_step == 1 && _fileName.isEmpty) {
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
              state: _fileName.isNotEmpty && _step > 1
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

  Widget _stepControls(BuildContext context, ControlsDetails details) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
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
        if (widget.badgeTitle.isNotEmpty) ...[
          Text(
            l10n
                .d('U levert bewijs aan voor: {badge}')
                .replaceAll('{badge}', widget.badgeTitle),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
        ],
        _typePicker(l10n),
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

  Widget _typePicker(AppLocalizations l10n) {
    final types = _types;
    if (_typesFailed) {
      return Text(l10n.d('De soorten bewijs konden niet worden geladen.'));
    }
    if (types == null) return const LinearProgressIndicator();
    if (types.isEmpty) {
      return Text(
        l10n.d(
          'Er zijn geen soorten bewijs beschikbaar. Vraag de organisatie ze te publiceren.',
        ),
      );
    }
    return DropdownButtonFormField<String>(
      key: const ValueKey('evidence-type'),
      initialValue: _typeId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: l10n.d('Soort bewijs'),
        errorText: _typeMissing
            ? l10n.d('Kies de soort bewijs die u aanlevert.')
            : null,
      ),
      items: [
        for (final type in types)
          DropdownMenuItem(value: type.id, child: Text(type.title)),
      ],
      onChanged: _submitting
          ? null
          : (value) => setState(() {
              _typeId = value;
              _typeMissing = false;
            }),
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
    if (_fileName.isEmpty) {
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
              _fileName.endsWith('.pdf')
                  ? Icons.picture_as_pdf_outlined
                  : Icons.image_outlined,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _fileName,
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
                  initialDate:
                      _validUntil ??
                      DateTime.now().add(const Duration(days: 365 * 2)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 20)),
                );
                if (picked != null) setState(() => _validUntil = picked);
              },
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _validUntil != null
                    ? MaterialLocalizations.of(
                        context,
                      ).formatFullDate(_validUntil!)
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
            switch (_submitError) {
              'checking' => l10n.d(
                'Het bestand wordt nog gecontroleerd. Probeer het over enkele minuten opnieuw.',
              ),
              'rejected' => l10n.d(
                'Het bestand is geweigerd bij de controle. Kies een ander bestand.',
              ),
              _ => l10n.d('Het aanleveren is mislukt. Probeer het opnieuw.'),
            },
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}
