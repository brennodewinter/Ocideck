import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import '../../l10n/app_localizations.dart';
import '../../state/ociserve_provider.dart';
import 'ociserve_file_browser.dart' show ociServeFileError;

class OciServePasskeysButton extends ConsumerWidget {
  const OciServePasskeysButton({super.key, this.enabled = true});
  final bool enabled;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ociServeProvider);
    if (state.errorCode == 'web_step_up_required' &&
        ref.watch(ociServeWebSessionClientProvider).available) {
      return FilledButton.icon(
        icon: const Icon(Icons.login),
        label: Text(context.l10n.d('Inloggen met passkey of andere methode')),
        onPressed: !enabled
            ? null
            : () async {
                final notifier = ref.read(ociServeProvider.notifier);
                notifier.prepareBrowserLogin();
                await notifier.login(forceLogin: true);
              },
      );
    }
    if (!state.authenticated ||
        state.account?.passwordlessEnrollable != true ||
        state.account?.passkeyManagementUrl == null) {
      return const SizedBox.shrink();
    }
    return TextButton.icon(
      icon: const Icon(Icons.key_outlined),
      label: Text(context.l10n.d('Passkeys beheren')),
      onPressed: !enabled
          ? null
          : () async {
              try {
                if (!await ref
                    .read(ociServeProvider.notifier)
                    .managePasskeys()) {
                  throw StateError('browser_refused');
                }
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ociServeFileError(context, error))),
                  );
                }
              }
            },
    );
  }
}
