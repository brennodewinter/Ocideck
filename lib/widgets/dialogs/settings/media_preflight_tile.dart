// The media preflight in the Videovergaderingen module card (F3.4a). It discloses
// two honest facts before any call is built: whether media end-to-end encryption
// is available on this platform (off on iOS/macOS, ketenkeuring Bevinding 6), and
// — on demand — whether the native WebRTC media stack actually loads on this
// device. The stack test touches `flutter_webrtc` through the injected
// [MeetingMediaCore]; the widget test drives it with a fake, so it never loads a
// real media stack.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../meetings/meeting_media_core.dart';
import '../../../meetings/meeting_media_core_webrtc.dart';
import '../../../meetings/meeting_provider.dart' show MeetingE2eeStatus;
import '../../../theme/app_theme.dart';

/// Builds the media core to probe. The default is the real `flutter_webrtc`
/// binding; a test injects a fake.
typedef MediaCoreFactory = MeetingMediaCore Function();

MeetingMediaCore _defaultMediaCore() => WebrtcMediaCore();

class MediaPreflightTile extends StatefulWidget {
  const MediaPreflightTile({super.key, this.createMediaCore = _defaultMediaCore});

  final MediaCoreFactory createMediaCore;

  @override
  State<MediaPreflightTile> createState() => _MediaPreflightTileState();
}

class _MediaPreflightTileState extends State<MediaPreflightTile> {
  bool _testing = false;
  bool? _stackOk; // null until tested

  Future<void> _testStack() async {
    setState(() => _testing = true);
    final core = widget.createMediaCore();
    bool ok;
    try {
      ok = await core.selfTest();
    } finally {
      await core.dispose();
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _stackOk = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListTile(
      leading: const Icon(Icons.enhanced_encryption_outlined),
      title: Text(
        l10n.d('Media (WebRTC)'),
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _e2eeText(l10n, mediaE2eeFor(defaultTargetPlatform)),
            style: TextStyle(fontSize: 12, color: AppTheme.slate600),
          ),
          if (_stackOk != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _stackOk!
                    ? l10n.d('De media-stack werkt op dit apparaat.')
                    : l10n.d('De media-stack kon niet laden op dit apparaat.'),
                style: TextStyle(
                  fontSize: 12,
                  color: _stackOk! ? AppTheme.successFg : AppTheme.dangerFg,
                ),
              ),
            ),
        ],
      ),
      trailing: _testing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton(
              onPressed: _testStack,
              child: Text(l10n.d('Media-stack testen')),
            ),
    );
  }
}

String _e2eeText(AppLocalizations l10n, MeetingE2eeStatus status) =>
    switch (status) {
      MeetingE2eeStatus.off => l10n.d(
        'Media-versleuteling (E2EE): uit op dit platform.',
      ),
      MeetingE2eeStatus.unknown => l10n.d(
        'Media-versleuteling (E2EE): nog niet beschikbaar.',
      ),
      MeetingE2eeStatus.on => l10n.d('Media-versleuteling (E2EE): aan.'),
    };
