import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../state/consent_provider.dart';
import '../../state/settings_provider.dart';
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
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final languageCode = ref.watch(
      settingsProvider.select((s) => s.languageCode),
    );

    return AlertDialog(
      scrollable: false,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Semantics(
                label: 'OciDeck',
                image: true,
                child: Image.asset(
                  'assets/images/ocideck-logo.png',
                  height: 40,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
              const Spacer(),
              // Language picker — the choice becomes the app's default language,
              // and the whole screen (via the app-level locale) re-renders in it.
              SizedBox(
                width: 210,
                child: DropdownButtonFormField<String>(
                  initialValue: languageCode,
                  isDense: true,
                  decoration: InputDecoration(
                    labelText: l10n.t('applicationLanguage'),
                    isDense: true,
                    prefixIcon: const Icon(Icons.language, size: 16),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final e in AppLocalizations.languageOptions)
                      DropdownMenuItem(
                        value: e.key,
                        child: Text(
                          e.value,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                  onChanged: (code) {
                    if (code == null) return;
                    ref.read(settingsProvider.notifier).setLanguageCode(code);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              l10n.d('Je keuze wordt de standaardtaal van de app.'),
              style: TextStyle(fontSize: 10, color: theme.colorScheme.outline),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.d('Welkom bij OciDeck'),
            style: theme.textTheme.titleLarge,
          ),
        ],
      ),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PrivacyStatementContent(),
              const SizedBox(height: 18),
              // Explicit, blocking consent: the accept button stays disabled
              // until the box is ticked.
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _agreed = !_agreed),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.2,
                    ),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Checkbox(
                        value: _agreed,
                        onChanged: (v) =>
                            setState(() => _agreed = v ?? false),
                        visualDensity: VisualDensity.compact,
                      ),
                      Expanded(
                        child: Text(
                          l10n.d(
                            'Ik ga akkoord met de EUPL 1.2-licentie en heb gelezen welke gegevens OciDeck bewaart.',
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
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.end,
      actions: [
        ElevatedButton(
          onPressed: _agreed ? () => _acceptConsent(ref) : null,
          child: Text(l10n.d('Akkoord gaan')),
        ),
      ],
    );
  }

  void _acceptConsent(WidgetRef ref) {
    ref.read(consentProvider.notifier).acceptConsent();
  }
}
