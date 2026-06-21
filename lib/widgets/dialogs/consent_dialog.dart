import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../state/consent_provider.dart';
import '../privacy_statement_content.dart';

class ConsentDialog extends ConsumerStatefulWidget {
  const ConsentDialog({super.key});

  @override
  ConsumerState<ConsentDialog> createState() => _ConsentDialogState();
}

class _ConsentDialogState extends ConsumerState<ConsentDialog> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(l10n.d('Welkom bij OciDeck')),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PrivacyStatementContent(showLicenseLink: true),
              const SizedBox(height: 18),
              // Confirmation Section
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.2,
                  ),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  l10n.d(
                    'Door op "Akkoord gaan" te klikken, accepteert u deze voorwaarden en gaat u akkoord met het gebruik van OciDeck.',
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => PrivacyStatementContent.launchLicenseOnline(),
          child: Text(l10n.d('Volledige licentie online')),
        ),
        const Spacer(),
        ElevatedButton(
          onPressed: () => _acceptConsent(ref),
          child: Text(l10n.d('Akkoord gaan')),
        ),
      ],
    );
  }

  void _acceptConsent(WidgetRef ref) {
    ref.read(consentProvider.notifier).acceptConsent();
  }
}
