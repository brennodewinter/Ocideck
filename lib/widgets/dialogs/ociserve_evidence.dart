import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_badge_readiness.dart';
import '../../models/ociserve_certificate.dart';
import '../../models/ociserve_evidence.dart';
import '../../models/ociserve_evidence_item.dart';
import '../../services/pdf_evidence_service.dart';
import '../../state/ociserve_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/atomic_file.dart';
import '../../utils/error_snackbar.dart';
import '../../utils/log.dart';
import '../reader/pdf_evidence_viewer.dart';
import 'ociserve_evidence_review.dart';
import 'ociserve_evidence_submit.dart';
import 'ociserve_portfolio_link.dart';

part 'parts/ociserve_evidence_actions.dart';

/// Het bewijsscherm — de vierde bestemming in de eLearning-zijbalk.
///
/// Toont bovenaan de badges die de cursist heeft, met hun geldigheidsdatum.
/// Daaronder per badge wat er nog ontbreekt. Onderaan de bewijsstukken met
/// hun status.
///
/// De ontwerpregel: begin bij de badge, niet bij een uploadvak.
class OciServeEvidence extends StatelessWidget {
  const OciServeEvidence({
    super.key,
    required this.qualifications,
    required this.evidenceUploads,
    required this.organizationId,
    required this.onRefresh,
    this.evidenceItems = const [],
    this.evidenceTypes = const [],
    this.participantId = '',
    this.readiness = const {},
    this.certificates = const [],
  });

  final List<OciServeQualification> qualifications;
  final List<EvidenceUpload> evidenceUploads;

  /// De ingediende bewijsstukken en de soorten waar ze bij horen. Een upload is
  /// pas een bewijsstuk voor een beoordelaar als hij is ingediend; de status
  /// van de beoordeling komt van het bewijsstuk, niet van de upload.
  final List<OciServeEvidenceItem> evidenceItems;
  final List<OciServeEvidenceType> evidenceTypes;
  final String participantId;

  /// Per badge (op `skill_version_id` van de kwalificatie) het leesmodel:
  /// welke eisen de badge stelt en welke de cursist al heeft afgevinkt.
  final Map<String, OciServeBadgeReadiness> readiness;

  /// De certificaten die de organisatie aan deze deelnemer heeft uitgegeven —
  /// ook de ingetrokken exemplaren, die hier met die status blijven staan.
  final List<OciServeCertificate> certificates;
  final String organizationId;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return CustomScrollView(
      key: const Key('ociserve-evidence'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(30, 0, 30, 30),
          sliver: SliverList.list(
            children: [
              _badgesSection(context, l10n, theme),
              const SizedBox(height: 24),
              _uploadsSection(context, l10n, theme),
              const SizedBox(height: 24),
              _certificatesSection(context, l10n, theme),
              const SizedBox(height: 24),
              _portfolioSection(context, l10n, theme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _badgesSection(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    if (qualifications.isEmpty) {
      return _emptySection(
        context,
        l10n,
        theme,
        Icons.verified_outlined,
        l10n.d('U hebt nog geen badges.'),
        l10n.d('Badges verschijnen hier zodra ze zijn toegekend.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.d('Mijn badges'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: l10n.d('Vernieuwen'),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final qual in qualifications) ...[
          _badgeCard(context, l10n, theme, qual),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _badgeCard(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    OciServeQualification qual,
  ) {
    final palette = AppPalette.of(theme);
    final title = qual.skillTitle.isEmpty ? l10n.d('Badge') : qual.skillTitle;
    final locale = MaterialLocalizations.of(context);
    final issuedStr = locale.formatFullDate(qual.issuedAt.toLocal());
    final expiresStr = qual.expiresAt != null
        ? locale.formatFullDate(qual.expiresAt!.toLocal())
        : null;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.verified_outlined,
                  color: qual.isActive
                      ? theme.colorScheme.primary
                      : palette.accentInk.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _statusChip(l10n, theme, qual.status),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text(
                  l10n
                      .d('Toegekend op {datum}')
                      .replaceAll('{datum}', issuedStr),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.accentInk.withValues(alpha: 0.7),
                  ),
                ),
                if (expiresStr != null)
                  Text(
                    l10n
                        .d('Geldig tot {datum}')
                        .replaceAll('{datum}', expiresStr),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.accentInk.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
            _requirementsBlock(context, l10n, theme, palette, qual),
          ],
        ),
      ),
    );
  }

  /// Per eis van de badge wat er al klopt en wat er nog ontbreekt. Een
  /// openstaande bewijseis opent het aanleverpad met de soort al ingevuld.
  Widget _requirementsBlock(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    AppPalette palette,
    OciServeQualification qual,
  ) {
    final model = readiness[qual.skillVersionId];
    if (model == null || model.requirements.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          model.ready
              ? l10n.d('Alle eisen zijn vervuld.')
              : l10n.d('Nog nodig voor deze badge'),
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        for (final requirement in model.requirements)
          _requirementRow(context, l10n, theme, palette, model, requirement),
      ],
    );
  }

  Widget _requirementRow(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    AppPalette palette,
    OciServeBadgeReadiness model,
    OciServeBadgeRequirement requirement,
  ) {
    final met = requirement.met;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: met
                ? theme.colorScheme.primary
                : palette.accentInk.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              requirement.title.isEmpty
                  ? _requirementKindLabel(l10n, requirement.kind)
                  : requirement.title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.accentInk.withValues(alpha: met ? 0.6 : 1.0),
              ),
            ),
          ),
          if (!met && requirement.kind == 'evidence')
            TextButton(
              onPressed: () => _openSubmit(
                context,
                badgeTitle: model.skillTitle,
                presetTypeSlug: requirement.evidenceType,
              ),
              child: Text(l10n.d('Aanleveren')),
            ),
        ],
      ),
    );
  }

  /// Eén woord voor een eis zonder eigen titel, zodat de rij nooit leeg is.
  String _requirementKindLabel(AppLocalizations l10n, String kind) =>
      switch (kind) {
        'evidence' => l10n.d('Bewijsstuk'),
        'exam' => l10n.d('Toets'),
        _ => l10n.d('Cursus'),
      };

  Widget _statusChip(
    AppLocalizations l10n,
    ThemeData theme,
    QualificationStatus status,
  ) {
    final (label, color) = switch (status) {
      QualificationStatus.approved => (
        l10n.d('Geaccepteerd'),
        theme.colorScheme.primary,
      ),
      QualificationStatus.pending => (
        l10n.d('In behandeling'),
        theme.colorScheme.tertiary,
      ),
      QualificationStatus.rejected => (
        l10n.d('Afgewezen'),
        theme.colorScheme.error,
      ),
      QualificationStatus.revoked => (
        l10n.d('Ingetrokken'),
        theme.colorScheme.error,
      ),
      QualificationStatus.expired => (
        l10n.d('Verlopen'),
        theme.colorScheme.error,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _uploadsSection(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    if (evidenceUploads.isEmpty) {
      return _emptySection(
        context,
        l10n,
        theme,
        Icons.upload_file_outlined,
        l10n.d('Nog geen bewijsstukken aangeleverd.'),
        l10n.d(
          'Bewijsstukken verschijnen hier zodra u iets aanlevert voor een badge.',
        ),
        action: FilledButton.icon(
          onPressed: () => _openSubmit(context),
          icon: const Icon(Icons.upload_outlined),
          label: Text(l10n.d('Bewijs aanleveren')),
        ),
      );
    }
    final locale = MaterialLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.d('Mijn bewijsstukken'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: () => _openSubmit(context),
              icon: const Icon(Icons.upload_outlined),
              label: Text(l10n.d('Aanleveren')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final upload in evidenceUploads) ...[
          _uploadCard(context, l10n, theme, locale, upload),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Future<void> _openSubmit(
    BuildContext context, {
    String? badgeTitle,
    String? presetTypeSlug,
  }) async {
    final refreshed = await OciServeEvidenceSubmit.show(
      context,
      organizationId: organizationId,
      participantId: participantId,
      badgeTitle:
          badgeTitle ??
          (qualifications.isNotEmpty ? qualifications.first.skillTitle : ''),
      presetTypeSlug: presetTypeSlug,
    );
    if (refreshed && context.mounted) onRefresh();
  }

  Widget _uploadCard(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    MaterialLocalizations locale,
    EvidenceUpload upload,
  ) {
    final palette = AppPalette.of(theme);
    final item = upload.isClean ? evidenceItemFor(upload, evidenceItems) : null;
    final (statusLabel, statusColor) = item != null
        ? evidenceItemLabel(l10n, theme, item.status)
        : _uploadStatusDisplay(l10n, theme, upload);
    // Een schone upload is alleen veilig bevonden; geaccepteerd is hij pas als
    // een beoordelaar het bewijsstuk heeft goedgekeurd.
    final statusMessage = item != null
        ? evidenceItemMessage(l10n, item)
        : upload.isClean
        ? l10n.d(
            'Het bestand is ontvangen en veilig bevonden. Het is nog niet ingediend voor beoordeling.',
          )
        : _uploadStatusMessage(l10n, locale, upload);
    final typeTitle = item == null
        ? null
        : evidenceTypeTitle(item, evidenceTypes);
    final nextStep = _uploadNextStep(l10n, upload);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  upload.declaredType.startsWith('application/pdf')
                      ? Icons.picture_as_pdf_outlined
                      : Icons.image_outlined,
                  color: palette.accentInk.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    upload.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              l10n
                  .d('Aangeleverd op {datum}')
                  .replaceAll(
                    '{datum}',
                    locale.formatFullDate(upload.createdAt.toLocal()),
                  ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.accentInk.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            if (typeTitle != null) ...[
              Text(
                l10n.d('Soort: {soort}').replaceAll('{soort}', typeTitle),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
            ],
            Text(statusMessage, style: theme.textTheme.bodyMedium),
            if (nextStep != null) ...[
              const SizedBox(height: 6),
              Text(
                nextStep,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            if (item != null &&
                (item.status == OciServeEvidenceContentStatus.ingediend ||
                    item.status ==
                        OciServeEvidenceContentStatus.inBehandeling)) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: _EvidenceWithdrawButton(
                  item: item,
                  organizationId: organizationId,
                  participantId: participantId,
                  onWithdrawn: onRefresh,
                ),
              ),
            ] else if (upload.isClean &&
                upload.declaredType.startsWith('application/pdf')) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: _EvidenceOpenButton(
                  upload: upload,
                  organizationId: organizationId,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Human-readable status message in mensentaal.
  /// Each status tells the learner what is happening, not just a label.
  String _uploadStatusMessage(
    AppLocalizations l10n,
    MaterialLocalizations locale,
    EvidenceUpload upload,
  ) {
    final dateStr = locale.formatFullDate(upload.createdAt.toLocal());
    return switch (upload.status) {
      EvidenceUploadStatus.pending =>
        l10n
            .d('In behandeling sinds {datum}. Meestal binnen twee werkdagen.')
            .replaceAll('{datum}', dateStr),
      EvidenceUploadStatus.uploaded =>
        l10n
            .d('In behandeling sinds {datum}. Meestal binnen twee werkdagen.')
            .replaceAll('{datum}', dateStr),
      EvidenceUploadStatus.clean => l10n.d(
        'Geaccepteerd. Het bewijsstuk is goedgekeurd.',
      ),
      EvidenceUploadStatus.rejected =>
        upload.rejectionReason != null && upload.rejectionReason!.isNotEmpty
            ? l10n
                  .d('Afgekeurd: {reden}')
                  .replaceAll('{reden}', upload.rejectionReason!)
            : l10n.d('Afgekeurd. De beoordelaar heeft geen reden opgegeven.'),
      EvidenceUploadStatus.failed => l10n.d(
        'Het uploaden is mislukt. Probeer het opnieuw.',
      ),
    };
  }

  /// The concrete next step for each status.
  /// A rejection without a next step is a bug, not a text — every
  /// negative outcome says what the learner can do now.
  String? _uploadNextStep(AppLocalizations l10n, EvidenceUpload upload) {
    return switch (upload.status) {
      EvidenceUploadStatus.pending => l10n.d(
        'Wordt verzonden zodra je online bent.',
      ),
      EvidenceUploadStatus.uploaded => null,
      EvidenceUploadStatus.clean => null,
      EvidenceUploadStatus.rejected => l10n.d(
        'Lever een nieuw of gecorrigeerd bestand aan.',
      ),
      EvidenceUploadStatus.failed => l10n.d('Lever het bestand opnieuw aan.'),
    };
  }

  (String, Color) _uploadStatusDisplay(
    AppLocalizations l10n,
    ThemeData theme,
    EvidenceUpload upload,
  ) {
    return switch (upload.status) {
      EvidenceUploadStatus.clean => (
        l10n.d('Gecontroleerd'),
        theme.colorScheme.primary,
      ),
      EvidenceUploadStatus.pending => (
        l10n.d('Opgegeven'),
        theme.colorScheme.tertiary,
      ),
      EvidenceUploadStatus.uploaded => (
        l10n.d('In behandeling'),
        theme.colorScheme.tertiary,
      ),
      EvidenceUploadStatus.rejected => (
        l10n.d('Afgekeurd'),
        theme.colorScheme.error,
      ),
      EvidenceUploadStatus.failed => (
        l10n.d('Mislukt'),
        theme.colorScheme.error,
      ),
    };
  }

  /// De certificaten die de organisatie heeft uitgegeven (#2426). De PDF
  /// draagt een verificatiegeheim, dus geen deel- of kopieerknop — alleen
  /// bekijken in de app en bewust bewaren naar een plek die de gebruiker kiest.
  Widget _certificatesSection(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    if (certificates.isEmpty) {
      return _emptySection(
        context,
        l10n,
        theme,
        Icons.workspace_premium_outlined,
        l10n.d('Nog geen certificaten.'),
        l10n.d(
          'Certificaten verschijnen hier zodra uw organisatie ze uitgeeft.',
        ),
      );
    }
    final locale = MaterialLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Certificaten'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        for (final certificate in certificates) ...[
          _certificateCard(context, l10n, theme, locale, certificate),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _certificateCard(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    MaterialLocalizations locale,
    OciServeCertificate certificate,
  ) {
    final palette = AppPalette.of(theme);
    final revoked = certificate.isRevoked;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.workspace_premium_outlined,
                  color: revoked
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    certificate.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (revoked
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary)
                            .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    revoked ? l10n.d('Ingetrokken') : l10n.d('Uitgegeven'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: revoked
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              l10n
                  .d('Uitgegeven op {datum}')
                  .replaceAll(
                    '{datum}',
                    locale.formatFullDate(certificate.issuedAt.toLocal()),
                  ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.accentInk.withValues(alpha: 0.7),
              ),
            ),
            if (certificate.certificateNumber.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                l10n
                    .d('Certificaatnummer: {nummer}')
                    .replaceAll('{nummer}', certificate.certificateNumber),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.accentInk.withValues(alpha: 0.7),
                ),
              ),
            ],
            if (revoked) ...[
              const SizedBox(height: 8),
              Text(
                certificate.revocationReason != null &&
                        certificate.revocationReason!.isNotEmpty
                    ? l10n
                          .d('Ingetrokken door uw organisatie: {reden}')
                          .replaceAll('{reden}', certificate.revocationReason!)
                    : l10n.d(
                        'Ingetrokken door uw organisatie. Deze verklaring geldt niet meer.',
                      ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: _CertificatePdfButton(
                certificate: certificate,
                organizationId: organizationId,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _portfolioSection(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Externe portefeuille'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: OciServePortfolioLink(
              organizationId: organizationId,
              participantId: participantId,
              evidenceTypes: evidenceTypes,
              onShared: onRefresh,
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptySection(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    IconData icon,
    String title,
    String subtitle, {
    Widget? action,
  }) {
    final palette = AppPalette.of(theme);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 48, color: palette.accentInk.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.accentInk.withValues(alpha: 0.6),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 16), action],
        ],
      ),
    );
  }
}
