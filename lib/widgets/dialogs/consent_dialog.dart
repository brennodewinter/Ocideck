import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/app_localizations.dart';
import '../../state/consent_provider.dart';

class ConsentDialog extends ConsumerStatefulWidget {
  const ConsentDialog({super.key});

  @override
  ConsumerState<ConsentDialog> createState() => _ConsentDialogState();
}

class _ConsentDialogState extends ConsumerState<ConsentDialog> {
  bool _licenseExpanded = false;

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
              // Privacy & Use Explanation
              Text(
                l10n.d('Privacy en gebruik'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.d(
                        'OciDeck is een lokale desktop-applicatie. Uw presentaties en gegevens worden uitsluitend op uw computer opgeslagen.',
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.d(
                        'De app verzamelt geen persoonlijke gegevens, geen statistieken en geen gebruiksgegevens. Uw privacy is onze prioriteit.',
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.d(
                        'Alle gegevens die u in OciDeck invoert, blijven op uw lokale systeem en worden niet naar externe servers gestuurd.',
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              // License Section
              ExpansionTile(
                title: Text(
                  l10n.d('Licentie (EUPL 1.2)'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                initiallyExpanded: _licenseExpanded,
                onExpansionChanged: (expanded) {
                  setState(() => _licenseExpanded = expanded);
                },
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: SingleChildScrollView(
                      child: Text(
                        l10n.d(_getLicenseText()),
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // Confirmation Section
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer
                      .withValues(alpha: 0.2),
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
          onPressed: () => _launchLicense(context),
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

  String _getLicenseText() {
    return '''SPDX-License-Identifier: EUPL-1.2
Copyright © Brenno de Winter

OciDeck is licensed under the European Union Public Licence (EUPL) v. 1.2.

The Work is provided under the terms of this Licence when the Licensor has
placed the following notice immediately following the copyright notice for
the Work:

Licensed under the EUPL

TERMS:
- The Licence: the European Union Public Licence v1.2
- The Original Work: OciDeck, distributed under this Licence
- Derivative Works: works created based upon OciDeck
- The Work: the Original Work or its Derivative Works

PERMISSIONS:
You are allowed to use, reproduce, modify, and distribute the Work, as long
as you comply with the terms of the EUPL v1.2.

CONDITIONS:
- You must include a copy of the Licence with any distribution
- You must state significant changes made to the Work
- You must maintain all copyright, patent and trademark notices
- You must provide clear notice of any modifications

The full EUPL v1.2 text is available at:
https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12''';
  }

  void _launchLicense(BuildContext context) async {
    const url = 'https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  void _acceptConsent(WidgetRef ref) {
    ref.read(consentProvider.notifier).acceptConsent();
  }
}
