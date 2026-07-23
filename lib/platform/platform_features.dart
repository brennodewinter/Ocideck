import 'package:flutter/foundation.dart';

import 'platform_features_io.dart'
    if (dart.library.html) 'platform_features_web.dart'
    as impl;

/// Whether the app runs in a browser (Flutter web).
bool get isWebPlatform => kIsWeb;

/// Desktop OS with native windowing (macOS, Windows, Linux).
bool get isDesktopNative => impl.isDesktopNative;

/// Linux-desktop, waar het klembord-schrijfpad via het eigen GTK-kanaal in
/// de runner loopt in plaats van via het pasteboard-pakket (#758).
bool get isLinuxDesktop => impl.isLinuxDesktop;

/// Whether this platform *could* run a native `git` subprocess at all — the
/// cheap, synchronous pre-check before the real runtime probe
/// (`nativeGitVersionProvider`, which actually invokes `git`). False on web and
/// mobile; true on desktop. It says nothing about whether `git` is installed.
bool get supportsNativeGit => impl.supportsNativeGit;

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
