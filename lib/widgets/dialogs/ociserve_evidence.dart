import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_evidence.dart';
import '../../theme/app_theme.dart';

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
    required this.onRefresh,
  });

  final List<OciServeQualification> qualifications;
  final List<EvidenceUpload> evidenceUploads;
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
    final title = qual.skillTitle.isEmpty
        ? l10n.d('Badge')
        : qual.skillTitle;
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
                  l10n.d('Toegekend op {datum}').replaceAll('{datum}', issuedStr),
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
          ],
        ),
      ),
    );
  }

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
      );
    }
    final locale = MaterialLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Mijn bewijsstukken'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        for (final upload in evidenceUploads) ...[
          _uploadCard(context, l10n, theme, locale, upload),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _uploadCard(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    MaterialLocalizations locale,
    EvidenceUpload upload,
  ) {
    final palette = AppPalette.of(theme);
    final (statusLabel, statusColor) = _uploadStatusDisplay(l10n, theme, upload);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          upload.declaredType.startsWith('application/pdf')
              ? Icons.picture_as_pdf_outlined
              : Icons.image_outlined,
          color: palette.accentInk.withValues(alpha: 0.6),
        ),
        title: Text(
          upload.filename,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
        subtitle: Text(
          l10n
              .d('Aangeleverd op {datum}')
              .replaceAll('{datum}', locale.formatFullDate(upload.createdAt.toLocal())),
          style: theme.textTheme.bodySmall?.copyWith(
            color: palette.accentInk.withValues(alpha: 0.6),
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
      ),
    );
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
        l10n.d('In wachtrij'),
        theme.colorScheme.tertiary,
      ),
      EvidenceUploadStatus.uploaded => (
        l10n.d('Wordt gecontroleerd'),
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

  Widget _emptySection(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    IconData icon,
    String title,
    String subtitle,
  ) {
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
        ],
      ),
    );
  }
}
