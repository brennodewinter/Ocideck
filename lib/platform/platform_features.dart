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

/// Netwerkbronnen voor decks (URL-import, Nextcloud/WebDAV).
///
/// Op web staat dit bewust uit: de CSP van de webbundel is `connect-src
/// 'self'` én de SSRF-checks van net_guard (dart:io) bestaan daar niet.
/// Cross-origin ophalen op web verruimen is een security-designkeuze die
/// expliciet moet worden afgestemd — niet iets om stilletjes aan te zetten.
bool get supportsNetworkDeckSources => impl.supportsNetworkDeckSources;
