import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

bool get isDesktopNative =>
    !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

bool get supportsNativeGit => isDesktopNative;

bool get supportsDualScreenPresenter => isDesktopNative;

bool get supportsLocalProjectFolders => !kIsWeb;

bool get supportsNetworkDeckSources => !kIsWeb;

String? get osHomeDirectory => kIsWeb
    ? null
    : (Platform.environment['HOME'] ?? Platform.environment['USERPROFILE']);
