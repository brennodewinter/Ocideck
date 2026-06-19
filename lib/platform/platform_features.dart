import 'package:flutter/foundation.dart';

import 'platform_features_io.dart'
    if (dart.library.html) 'platform_features_web.dart'
    as impl;

/// Whether the app runs in a browser (Flutter web).
bool get isWebPlatform => kIsWeb;

/// Desktop OS with native windowing (macOS, Windows, Linux).
bool get isDesktopNative => impl.isDesktopNative;

/// Dual-screen presenter (separate audience window).
bool get supportsDualScreenPresenter => impl.supportsDualScreenPresenter;

/// Full filesystem access for project folders and sidecars.
bool get supportsLocalProjectFolders => impl.supportsLocalProjectFolders;
