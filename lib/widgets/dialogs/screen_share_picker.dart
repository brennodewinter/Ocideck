// De kiezer voor schermdelen (#2537): welk scherm of welk venster de
// gebruiker live wil verzenden, met de miniatuur die het OS meelevert.
// Alleen op platforms met een eigen bronlijst — op web toont de browser zijn
// eigen kiezer en komt dit dialoog niet voor (de seam meldt dan een lege
// lijst en CallPanel roept startScreenShare() zonder sourceId aan).

import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../meetings/meeting_media_core.dart' show MeetingScreenSource;
import '../../theme/app_theme.dart';
import '../../utils/image_limits.dart' show cappedMemoryImage;

/// Kiest één [MeetingScreenSource] — geeft die terug via `pop`, null bij
/// annuleren. Puur een keuzelijst: de capture start pas bij de caller.
class ScreenSharePickerDialog extends StatelessWidget {
  const ScreenSharePickerDialog({super.key, required this.sources});

  final List<MeetingScreenSource> sources;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Kies wat je deelt')),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [for (final source in sources) _SourceTile(source: source)],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Annuleren')),
        ),
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source});

  final MeetingScreenSource source;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final thumb = source.thumbnail;
    return ListTile(
      leading: thumb != null
          ? Image(
              // OS-geleverde miniatuur — toch begrensd decoden (de guard
              // staat geen kale MemoryImage toe, en begrenzen kan nooit
              // kwaad).
              image: cappedMemoryImage(thumb),
              width: 80,
              height: 45,
              fit: BoxFit.cover,
            )
          : Icon(
              source.isWindow
                  ? Icons.web_asset_outlined
                  : Icons.desktop_windows_outlined,
              color: AppTheme.slate500,
            ),
      title: Text(source.label, overflow: TextOverflow.ellipsis),
      subtitle: Text(source.isWindow ? l10n.d('Venster') : l10n.d('Scherm')),
      onTap: () => Navigator.of(context).pop(source),
    );
  }
}
