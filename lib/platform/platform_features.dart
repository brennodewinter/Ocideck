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

/// De thuismap van de gebruiker volgens het OS (`$HOME`/`%USERPROFILE%`), of
/// null op web. Voor leesbare padweergave (`~`-afkorting) in open-lijsten.
String? get osHomeDirectory => impl.osHomeDirectory;

/// Nextcloud/WebDAV als deck-bron (bladeren, openen, terugschrijven).
///
/// Op web staat dit bewust uit: de WebDAV-client draait op dart:io met eigen
/// SSRF-pinning, en vanuit de browser vergt WebDAV bovendien CORS-instellingen
/// op de server — een designkeuze die expliciet met de beheerder afgestemd
/// moet worden. URL-import valt hier bewust NIET onder: die werkt op web via
/// de browser (CORS + CSP `connect-src 'self' https:`) met dezelfde
/// security-gate als op desktop.
bool get supportsNetworkDeckSources => impl.supportsNetworkDeckSources;
