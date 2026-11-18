import 'dart:io';

/// Resolves Flutter 3.50 content-hashed assets as well as desktop asset paths.
/// Multiple matches are ambiguous: an incremental build must not silently use
/// an older copy merely because its directory entry happened to come first.
File? bundledAsset(Directory assets, String path) {
  final direct = File('${assets.path}/$path');
  if (direct.existsSync()) return direct;
  final slash = path.lastIndexOf('/');
  final parent = Directory('${assets.path}/${path.substring(0, slash + 1)}');
  if (!parent.existsSync()) return null;
  final name = path.substring(slash + 1);
  final dot = name.lastIndexOf('.');
  final stem = dot < 0 ? name : name.substring(0, dot);
  final suffix = dot < 0 ? '' : name.substring(dot);
  final pattern = RegExp(
    '^${RegExp.escape(stem)}\\.[0-9a-f]{8}${RegExp.escape(suffix)}\$',
  );
  final matches = parent.listSync().whereType<File>().where(
    (file) => pattern.hasMatch(file.uri.pathSegments.last),
  );
  return matches.length == 1 ? matches.single : null;
}
