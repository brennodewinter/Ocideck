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
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: 'OciDeck',
            image: true,
            child: Image.asset(
              'assets/images/ocideck-logo.png',
              height: 72,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
          const SizedBox(height: 12),
          Text(l10n.d('Welkom bij OciDeck')),
        ],
      ),
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
      // Split the two actions to opposite ends. AlertDialog lays its actions out
      // in an OverflowBar (not a Flex), so a Spacer/Expanded here throws a
      // parentData subtype error at layout time (swallowed into the release
      // ErrorWidget placeholder). actionsAlignment is the correct lever.
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => PrivacyStatementContent.launchLicenseOnline(),
          child: Text(l10n.d('Volledige licentie online')),
        ),
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
