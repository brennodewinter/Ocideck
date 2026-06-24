import 'dart:io';
import 'package:flutter/services.dart';
import '../utils/log.dart';

/// Receives file paths from the macOS host when the user opens a `.md` or
/// `.ocideck` file via Finder (double-click / "Open With"). See
/// `macos/Runner/AppDelegate.swift` for the native side.
///
/// On [start] it drains any files the app was launched with (cold start) and
/// then listens for files opened while the app is already running (warm start).
class OpenFileChannel {
  static const _channel = MethodChannel('ocideck/open_file');

  /// Called with one or more file paths to open. Routing (markdown vs package)
  /// is the caller's responsibility.
  final Future<void> Function(List<String> paths) onOpenFiles;

  OpenFileChannel(this.onOpenFiles);

  Future<void> start() async {
    if (!Platform.isMacOS) return;
    _channel.setMethodCallHandler(_handle);
    try {
      final launch = await _channel.invokeMethod<List<dynamic>>(
        'getLaunchFiles',
      );
      final paths = _stringList(launch);
      if (paths.isNotEmpty) await onOpenFiles(paths);
    } on MissingPluginException {
      // No native handler (e.g. running an older build): nothing to do.
    } catch (e) {
      logWarning('OpenFileChannel.start: getLaunchFiles failed', e);
    }
  }

  Future<dynamic> _handle(MethodCall call) async {
    if (call.method == 'openFiles') {
      final paths = _stringList(call.arguments);
      if (paths.isNotEmpty) await onOpenFiles(paths);
    }
    return null;
  }

  List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<String>().toList();
  }
}
