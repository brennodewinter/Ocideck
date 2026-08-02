import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../state/consent_provider.dart';
import '../../state/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/brand_logo.dart';
import '../language_flag.dart';
import '../privacy_statement_content.dart';

class ConsentDialog extends ConsumerStatefulWidget {
  const ConsentDialog({super.key});

  @override
  ConsumerState<ConsentDialog> createState() => _ConsentDialogState();
}

class _ConsentDialogState extends ConsumerState<ConsentDialog> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final languageCode = ref.watch(
      settingsProvider.select((s) => s.languageCode),
    );

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ConsentHeader(
              languageCode: languageCode,
              onLanguageChanged: (code) =>
                  ref.read(settingsProvider.notifier).setLanguageCode(code),
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            Flexible(
              child: LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth >= 760
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Expanded(flex: 9, child: _ConsentWelcomePane()),
                          Expanded(flex: 11, child: _consentPane(l10n, theme)),
                        ],
                      )
                    : _consentPane(l10n, theme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _consentPane(AppLocalizations l10n, ThemeData theme) {
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 30, 32, 18),
              child: _ConsentSummary(l10n: l10n),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(32, 14, 32, 24),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Column(
              children: [
                _ConsentCheckbox(
                  value: _agreed,
                  onChanged: (value) =>
                      setState(() => _agreed = value ?? false),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _agreed ? () => _acceptConsent(ref) : null,
                    child: Text(l10n.d('Akkoord gaan')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _acceptConsent(WidgetRef ref) {
    ref.read(consentProvider.notifier).acceptConsent();
  }
}

class _ConsentHeader extends StatelessWidget {
  final String languageCode;
  final ValueChanged<String> onLanguageChanged;

  const _ConsentHeader({
    required this.languageCode,
    required this.onLanguageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Semantics(
            label: l10n.d('OciDeck'),
            image: true,
            child: Image.asset(
              BrandLogo.ociDeck.assetKey,
              height: 38,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            l10n.d('OciDeck'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Spacer(),
          SizedBox(
            width: 210,
            child: DropdownButtonFormField<String>(
              initialValue: languageCode,
              isExpanded: true,
              isDense: true,
              decoration: InputDecoration(
                labelText: l10n.t('applicationLanguage'),
                isDense: true,
                prefixIcon: const Icon(Icons.language, size: 16),
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final entry in AppLocalizations.languageOptions)
                  DropdownMenuItem(
                    value: entry.key,
                    child: languageOptionRow(
                      entry.key,
                      entry.value,
                      fontSize: 13,
                    ),
                  ),
              ],
              onChanged: (code) {
                if (code != null) onLanguageChanged(code);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentWelcomePane extends StatelessWidget {
  const _ConsentWelcomePane();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
            theme.colorScheme.surface,
          ],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(38),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d('OciDeck'),
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppPalette.of(theme).accentInk,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.d('Welkom bij OciDeck'),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.d(
                'Presentaties die gewone Markdown-bestanden blijven: leesbaar, doorzoekbaar en te openen met elke editor.',
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 28),
            _ConsentPromise(
              icon: Icons.person_outline,
              title: l10n.d('Lokaal'),
              subtitle: l10n.d('Wat OciDeck op dit apparaat bewaart'),
            ),
            _ConsentPromise(
              icon: Icons.privacy_tip_outlined,
              title: l10n.d('Privacy'),
              subtitle: l10n.d('De privacycontrole'),
            ),
            _ConsentPromise(
              icon: Icons.balance_outlined,
              title: l10n.d('Licentie (EUPL 1.2)'),
              subtitle: l10n.d('Lees de volledige licentie'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsentPromise extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ConsentPromise({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 18, color: AppPalette.of(theme).accentInk),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentSummary extends StatelessWidget {
  final AppLocalizations l10n;

  const _ConsentSummary({required this.l10n});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Welkom bij OciDeck'),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.d(
            'OciDeck is vrije software onder de EUPL 1.2-licentie. Voordat je begint, vragen we je de licentie te accepteren. Hieronder lees je ook welke gegevens OciDeck op dit apparaat bewaart en wanneer er iets je apparaat verlaat.',
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 22),
        _ConsentSummaryRow(
          icon: Icons.gavel_outlined,
          title: l10n.d('Licentie (EUPL 1.2)'),
          subtitle: l10n.d('Lees de volledige licentie'),
        ),
        _ConsentSummaryRow(
          icon: Icons.save_outlined,
          title: l10n.d('Wat OciDeck op dit apparaat bewaart'),
          subtitle: l10n.d('Lokaal'),
        ),
        const SizedBox(height: 8),
        Material(
          color: Colors.transparent,
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 12),
            title: Text(
              '${l10n.d('Lees de volledige licentie')} · '
              '${l10n.d('Privacy')}',
              style: TextStyle(
                color: AppPalette.of(theme).accentInk,
                fontWeight: FontWeight.w600,
              ),
            ),
            children: const [PrivacyStatementContent()],
          ),
        ),
      ],
    );
  }
}

class _ConsentSummaryRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ConsentSummaryRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: AppPalette.of(theme).accentInk),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;

  const _ConsentCheckbox({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.28),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: value, onChanged: onChanged),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.d(
                    'Ik ga akkoord met de EUPL 1.2-licentie en heb gelezen welke gegevens OciDeck bewaart.',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
