import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

bool get isDesktopNative =>
    !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

bool get supportsDualScreenPresenter => isDesktopNative;

bool get supportsLocalProjectFolders => !kIsWeb;
