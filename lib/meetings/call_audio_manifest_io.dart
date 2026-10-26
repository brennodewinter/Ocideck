// Desktop-helft van de bronnenprovenance (#2529): `sources.json` naast de
// opnamewav's in de sessie-stagingmap. De herstelperiode van de staging
// geldt dus ook voor de provenance — ze verdwijnen samen.
import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/atomic_file.dart';

Future<void> writeCallSources(String stagingDir, String json) =>
    writeStringAtomic(File(p.join(stagingDir, 'sources.json')), json);
