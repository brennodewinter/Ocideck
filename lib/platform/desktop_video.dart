import 'package:flutter/foundation.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';

bool _registered = false;

/// Each presentation window runs main in its own engine. Windows' federated
/// video_player_win backend registers automatically; Linux needs this adapter.
void registerDesktopVideo() {
  if (!_registered &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.linux) {
    VideoPlayerMediaKit.ensureInitialized(linux: true);
    _registered = true;
  }
}
