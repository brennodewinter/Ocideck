// Part of the ociserve_evidence library — see ../ociserve_evidence.dart.
// Split out for the 1000-line gate: the three action widgets that do async
// work (withdraw, certificate PDF, open) live here; imports stay in the main
// file.
part of '../ociserve_evidence.dart';

/// Trekt een bewijsstuk in dat nog in de beoordeling staat — pas afgeschafte
/// deling wordt niet meer bekeken door de beoordelaar.
class _EvidenceWithdrawButton extends ConsumerStatefulWidget {
  const _EvidenceWithdrawButton({
    required this.item,
    required this.organizationId,
    required this.participantId,
    required this.onWithdrawn,
  });

  final OciServeEvidenceItem item;
  final String organizationId;
  final String participantId;
  final VoidCallback onWithdrawn;

  @override
  ConsumerState<_EvidenceWithdrawButton> createState() =>
      _EvidenceWithdrawButtonState();
}

class _EvidenceWithdrawButtonState
    extends ConsumerState<_EvidenceWithdrawButton> {
  bool _loading = false;

  Future<void> _withdraw() async {
    final l10n = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.d('Bewijsstuk intrekken?')),
        content: Text(
          l10n.d(
            'De beoordelaar ziet dit stuk dan niet meer. '
            'U kunt later opnieuw bewijs aanleveren.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.d('Intrekken')),
          ),
        ],
      ),
    );
    if (!mounted || sure != true) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(ociServeProvider.notifier)
          .withdrawEvidenceItem(
            organizationId: widget.organizationId,
            participantId: widget.participantId,
            evidenceItemId: widget.item.id,
          );
      if (mounted) widget.onWithdrawn();
    } catch (error, stack) {
      logError('OciServe: bewijsstuk intrekken', error.runtimeType, stack);
      if (mounted) {
        showErrorSnackBar(
          ScaffoldMessenger.of(context),
          context.l10n,
          context.l10n.d('Het intrekken is mislukt. Probeer het opnieuw.'),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: _loading ? null : _withdraw,
    icon: _loading
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.undo_outlined),
    label: Text(context.l10n.d('Intrekken')),
  );
}

/// Haalt de certificaat-PDF op en biedt "Bekijken" en "Bewaren". De bytes
/// gaan rechtstreeks naar de viewer of naar een pad dat de gebruiker zelf
/// koos — geen tussencache, geen deelknop (het verificatiegeheim hoort bij
/// dit document).
class _CertificatePdfButton extends ConsumerStatefulWidget {
  const _CertificatePdfButton({
    required this.certificate,
    required this.organizationId,
  });

  final OciServeCertificate certificate;
  final String organizationId;

  @override
  ConsumerState<_CertificatePdfButton> createState() =>
      _CertificatePdfButtonState();
}

class _CertificatePdfButtonState extends ConsumerState<_CertificatePdfButton> {
  bool _loading = false;

  String get _fileName {
    final number = widget.certificate.certificateNumber;
    final base = number.isEmpty ? widget.certificate.id : number;
    return 'certificaat-$base.pdf';
  }

  Future<Uint8List?> _download() async {
    setState(() => _loading = true);
    try {
      return await ref
          .read(ociServeProvider.notifier)
          .certificatePdf(
            organizationId: widget.organizationId,
            certificateId: widget.certificate.id,
          );
    } on Object {
      if (mounted) {
        showErrorSnackBar(
          ScaffoldMessenger.of(context),
          context.l10n,
          context.l10n.d(
            'Het certificaat kon niet worden opgehaald. Probeer het opnieuw.',
          ),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _view() async {
    final bytes = await _download();
    if (bytes == null || !mounted) return;
    await PdfEvidenceViewer.open(context, bytes: bytes, fileName: _fileName);
  }

  Future<void> _save() async {
    final bytes = await _download();
    if (bytes == null || !mounted) return;
    final location = await getSaveLocation(suggestedName: _fileName);
    if (location == null || !mounted) return;
    try {
      await writeBytesAtomic(File(location.path), bytes);
    } on Object {
      if (mounted) {
        showErrorSnackBar(
          ScaffoldMessenger.of(context),
          context.l10n,
          context.l10n.d(
            'Het certificaat kon niet worden bewaard. Probeer het opnieuw.',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: 8,
      children: [
        FilledButton.tonalIcon(
          onPressed: _loading ? null : _view,
          icon: _loading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.visibility_outlined),
          label: Text(l10n.d('Bekijken')),
        ),
        TextButton.icon(
          onPressed: _loading ? null : _save,
          icon: const Icon(Icons.download_outlined),
          label: Text(l10n.d('Bewaren')),
        ),
      ],
    );
  }
}

class _EvidenceOpenButton extends ConsumerStatefulWidget {
  const _EvidenceOpenButton({
    required this.upload,
    required this.organizationId,
  });

  final EvidenceUpload upload;
  final String organizationId;

  @override
  ConsumerState<_EvidenceOpenButton> createState() =>
      _EvidenceOpenButtonState();
}

class _EvidenceOpenButtonState extends ConsumerState<_EvidenceOpenButton> {
  bool _loading = false;

  Future<void> _open() async {
    setState(() => _loading = true);
    try {
      final bytes = await ref
          .read(ociServeProvider.notifier)
          .downloadEvidence(
            organizationId: widget.organizationId,
            evidenceId: widget.upload.id,
          );
      if (!mounted) return;
      if (!isSupportedPdfEvidence(bytes)) {
        showErrorSnackBar(
          ScaffoldMessenger.of(context),
          context.l10n,
          bytes.length > maxPdfEvidenceBytes
              ? context.l10n.d('Dit bestand is te groot om te openen.')
              : context.l10n.d('Kon dit bestand niet openen.'),
        );
        return;
      }
      await PdfEvidenceViewer.open(
        context,
        bytes: bytes,
        fileName: widget.upload.filename,
      );
    } on Object {
      if (mounted) {
        showErrorSnackBar(
          ScaffoldMessenger.of(context),
          context.l10n,
          context.l10n.d('Kon dit bestand niet openen.'),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
    onPressed: _loading ? null : _open,
    icon: _loading
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.visibility_outlined),
    label: Text(context.l10n.d('Openen')),
  );
}
