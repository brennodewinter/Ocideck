import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Only app-owned downloaded CVE data; never presentation files or sidecars.
Future<void> removeRetiredMiauwData({Directory? supportDirectory}) async {
  final support = supportDirectory ?? await getApplicationSupportDirectory();
  final cache = Directory(p.join(support.path, 'cve'));
  // Do not follow a substituted symlink outside the application directory.
  if (await FileSystemEntity.type(cache.path, followLinks: false) ==
      FileSystemEntityType.directory) {
    await cache.delete(recursive: true);
  }
}
