import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_models.dart';
import '../../services/ociserve/ociserve_http.dart';
import '../../state/ociserve_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_limits.dart';
import '../../utils/image_signature.dart';
import '../../utils/log.dart';

class OciServeAccountAvatar extends ConsumerWidget {
  const OciServeAccountAvatar({
    super.key,
    required this.account,
    required this.name,
    this.size = 36,
    this.editable = false,
  });

  final OciServeAccount account;
  final String name;
  final double size;

  /// De profielfoto wijzigen/verwijderen staat alleen open op plaatsen waar
  /// de gebruiker zijn eigen profiel beheert — [editable] is daarom niet de
  /// standaard maar een bewuste keuze van de aanroeper.
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    Widget fallback() => CircleAvatar(
      radius: size / 2,
      backgroundColor: theme.colorScheme.secondary,
      foregroundColor: AppTheme.labelOn(theme.colorScheme.secondary),
      child: Text(_initials(name)),
    );
    final Widget image;
    if (account.avatarHash.isEmpty) {
      image = fallback();
    } else {
      image = SizedBox.square(
        dimension: size,
        child: ClipOval(
          child: Image(
            key: const Key('ociserve-account-avatar'),
            image: CappedImage(
              'ociserve-avatar:${account.avatarHash}',
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
    if (!editable) return image;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        image,
        Positioned(right: -6, bottom: -6, child: _AvatarEditButton(size: size)),
      ],
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

/// De kleine bewerkknop op de avatar in het leerprofiel. Houdt zijn eigen
/// busy-stand en foutmelding bij: een mislukte upload mag de rest van het
/// scherm niet meenemen.
class _AvatarEditButton extends ConsumerStatefulWidget {
  const _AvatarEditButton({required this.size});

  final double size;

  @override
  ConsumerState<_AvatarEditButton> createState() => _AvatarEditButtonState();
}

class _AvatarEditButtonState extends ConsumerState<_AvatarEditButton> {
  static const int _maxAvatarBytes = 5 * 1024 * 1024;

  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return IconButton(
      key: const Key('ociserve-avatar-edit'),
      tooltip: l10n.d('Profielfoto wijzigen'),
      onPressed: _busy ? null : _editMenu,
      style: IconButton.styleFrom(
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.primary,
        minimumSize: const Size(28, 28),
        padding: const EdgeInsets.all(4),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      icon: _busy
          ? const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.photo_camera_outlined, size: 15),
    );
  }

  Future<void> _editMenu() async {
    final l10n = context.l10n;
    final hasAvatar =
        ref.read(ociServeProvider).account?.avatarHash.isNotEmpty ?? false;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('ociserve-avatar-replace'),
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.d('Nieuwe profielfoto kiezen')),
              onTap: () => Navigator.pop(sheetContext, 'replace'),
            ),
            if (hasAvatar)
              ListTile(
                key: const Key('ociserve-avatar-remove'),
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(l10n.d('Profielfoto verwijderen')),
                onTap: () => Navigator.pop(sheetContext, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'remove') {
      await _remove();
    } else {
      await _replace();
    }
  }

  /// Kiest een lokaal beeldbestand en stuurt het op. De MIME volgt de
  /// handtekening van de bytes, niet de bestandsnaam — een `foto.png` die
  /// eigenlijk iets anders is, wordt hier afgewezen in plaats van op de
  /// server.
  Future<void> _replace() async {
    // Web is hier onbereikbaar: eLearning werkt alleen waar een sleutelbos
    // is (platformCanStoreSecrets), dus deze knop komt nooit in een build
    // waar FilePicker geen echt bestand levert.
    final l10n = context.l10n;
    final file = await FilePicker.pickFile(
      type: FileType.image,
      dialogTitle: l10n.d('Profielfoto kiezen'),
    );
    if (!mounted || file == null) return;
    final bytes = await file.readAsBytes();
    final mime = imageMimeFromBytes(bytes);
    if (bytes.isEmpty ||
        bytes.length > _maxAvatarBytes ||
        mime == null ||
        (mime != 'image/png' && mime != 'image/jpeg' && mime != 'image/webp')) {
      _fail(
        l10n.d('Kies een PNG-, JPEG- of WebP-afbeelding van maximaal 5 MB.'),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(ociServeProvider.notifier)
          .replaceAccountAvatar(bytes, mime);
    } on OciServeException catch (error) {
      _fail(_avatarError(l10n, error));
      return;
    } catch (error, stack) {
      logError('OciServe: profielfoto wijzigen', error.runtimeType, stack);
      _fail(_avatarError(l10n, null));
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final l10n = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.d('Profielfoto verwijderen')),
        content: Text(
          l10n.d(
            'De organisatie en andere deelnemers zien dan geen foto meer bij uw account.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.d('Verwijderen')),
          ),
        ],
      ),
    );
    if (!mounted || sure != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(ociServeProvider.notifier).removeAccountAvatar();
    } catch (error, stack) {
      logError('OciServe: profielfoto verwijderen', error.runtimeType, stack);
      _fail(_avatarError(l10n, error is OciServeException ? error : null));
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _avatarError(AppLocalizations l10n, OciServeException? error) {
    if (error != null && error.statusCode == 413) {
      return l10n.d('De afbeelding is te groot. Kies een kleiner bestand.');
    }
    return l10n.d('De profielfoto is niet opgeslagen. Probeer het opnieuw.');
  }

  void _fail(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
