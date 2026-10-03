// Een sleutelhanger in het geheugen voor de tests van de redactiesleutel.

import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Een sleutelhanger in het geheugen die kapot kan gaan op de manieren waarop een echte dat
/// doet: niet te lezen, niet te schrijven, of schrijven zonder iets te bewaren.
class FormKeyVault extends FlutterSecureStorage {
  FormKeyVault() : super();

  final Map<String, String> data = {};
  final List<String> writes = [];
  bool failRead = false;
  bool failWrite = false;
  bool dropWrites = false;

  /// Hoe vaak er is gelezen: wie wil weten of iets één keer of twee keer is gedaan.
  int reads = 0;

  /// Houdt lezen of schrijven vast tot de test het loslaat: zo is te zien wat er gebeurt terwijl
  /// de sleutelhanger nog bezig is.
  Completer<void>? readGate;
  Completer<void>? writeGate;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    reads++;
    await readGate?.future;
    if (failRead) throw Exception('sleutelhanger vergrendeld');
    return data[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await writeGate?.future;
    if (failWrite) throw Exception('schrijven geweigerd');
    writes.add(key);
    if (dropWrites) return;
    data[key] = value!;
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => data.remove(key);
}
