import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

import '../utils/html_to_markdown.dart';
import '../utils/log.dart';

const MethodChannel kClipboardHtmlChannel = MethodChannel('ocideck/clipboard');

/// Windows/Android: `pasteboard`. macOS/Linux: eigen native kanaal.
Future<String?> readClipboardHtmlImpl() async {
  try {
    final fromPackage = await Pasteboard.html;
    if (fromPackage != null && fromPackage.isNotEmpty) {
      return _cap(fromPackage);
    }
  } catch (e) {
    logWarning('Pasteboard.html failed', e);
  }
  if (!Platform.isMacOS && !Platform.isLinux) return null;
  try {
    final fromChannel = await kClipboardHtmlChannel.invokeMethod<String>(
      'html',
    );
    if (fromChannel == null || fromChannel.isEmpty) return null;
    return _cap(fromChannel);
  } on MissingPluginException {
    return null;
  } catch (e) {
    logWarning('clipboard html channel failed', e);
    return null;
  }
}

String? _cap(String html) {
  if (html.length > kClipboardHtmlMaxChars) return null;
  return html;
}
