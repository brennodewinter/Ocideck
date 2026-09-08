import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/ociserve_models.dart';
import '../../state/ociserve_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_limits.dart';
import '../../utils/log.dart';

class OciServeAccountAvatar extends ConsumerWidget {
  const OciServeAccountAvatar({
    super.key,
    required this.account,
    required this.name,
    this.size = 36,
  });

  final OciServeAccount account;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    Widget fallback() => CircleAvatar(
      radius: size / 2,
      backgroundColor: theme.colorScheme.secondary,
      foregroundColor: AppTheme.labelOn(theme.colorScheme.secondary),
      child: Text(_initials(name)),
    );
    if (account.avatarHash.isEmpty) return fallback();
    final server = ref.read(ociServeProvider).settings.normalizedBaseUrl;
    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: Image(
          key: const Key('ociserve-account-avatar'),
          image: CappedImage(
            '$server|avatar|${account.avatarHash}',
            () => ref
                .read(ociServeProvider.notifier)
                .accountAvatar(account.avatarHash),
          ),
          fit: BoxFit.cover,
          semanticLabel: name,
          errorBuilder: (context, error, stack) {
            logWarning('OciServe: profielfoto tonen mislukt', error);
            return fallback();
          },
        ),
      ),
    );
  }

  static String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    return words
        .take(2)
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase())
        .join();
  }
}
