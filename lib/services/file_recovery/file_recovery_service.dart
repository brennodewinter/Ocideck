import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../models/settings.dart';
import '../../utils/atomic_file.dart';
import '../../utils/log.dart';

/// Wat er met één projectlid in de herstelkopie is gebeurd (#2880).
enum RecoveryDisposition {
  /// Byte-exact meegekomen op zijn eigen plek in de kopie.
  copied,

  /// Niet te interpreteren: de bytes staan bewaard onder `_herstel/` en de
  /// levende plek in de kopie is leeg, zodat de kopie zelf weer opent.
  quarantined,

  /// De bron gaf geen leesbare bytes — er is niets verdwenen, maar er is ook
  /// niets gered. Eerlijk gemeld, nooit als "hersteld" geteld.
  unreadable,
}

/// Eén lid van de herstelkopie: waar hij stond, hoeveel bytes, de bron-hash en
/// wat ermee gebeurde. De hash dekt de oorspronkelijke bytes — de kopie en het
/// origineel zijn zo te vergelijken zonder dat iets op vertrouwen rust.
class RecoveredMember {
  final String path;
  final int byteCount;
  final String sha256;
  final RecoveryDisposition disposition;
  final String? note;

  const RecoveredMember(
    this.path,
    this.byteCount,
    this.sha256,
    this.disposition, {
    this.note,
  });

  Map<String, Object?> toJson() => {
    'path': path,
    'bytes': byteCount,
    'sha256': sha256,
    'disposition': disposition.name,
    if (note != null) 'note': note,
  };
}

/// Uitkomst van [FileRecoveryService.recoverCopy].
class FileRecoveryResult {
  /// De nieuwe projectmap waarin de kopie staat (naast de bron).
  final Directory directory;
  final List<RecoveredMember> members;
  final List<String> diagnoses;
  final String reportPath;
  final String manifestPath;

  /// Het `.md` van de kopie, als die op zijn levende plek staat — de
  /// aanroeper kan hem direct aanbieden om te openen.
  final String? recoveredMarkdownPath;

  const FileRecoveryResult({
    required this.directory,
    required this.members,
    required this.diagnoses,
    required this.reportPath,
    required this.manifestPath,
    this.recoveredMarkdownPath,
  });
}

/// Bestandsherstel na een openfout (#2880).
///
/// De route is bewust saai: kopieer elk projectlid **byte-exact** naar een
/// nieuwe map, en verplaats bínnen die kopie alleen de leden waarvan bewezen
/// is dat ze de open breken naar `_herstel/` — een kapot `ocideck-style.json`
/// mag een intacte presentatie niet gijzelen (#2877). Niemand raadt naar
/// ontbrekende inhoud: wat niet te interpreteren is, blijft als origineel
/// bewaard en wordt als zodanig gerapporteerd.
///
/// Het origineel wordt nooit aangeraakt. Een tweede poging maakt een nieuwe
/// map (`-herstel-2`, `-3`, …) en overschrijft de eerste kopie niet.
class FileRecoveryService {
  /// Map binnen de kopie waar geweigerde leden, manifest en rapport staan.
  static const quarantineDir = '_herstel';

  static const _sidecarExtensions = [
    '.ink.json',
    '.user-notes.json',
    '.miauw.json',
    '.dismissals.json',
    '.seal.json',
  ];

  /// Herstel `[sourceMdPath]` en zijn projectleden in een nieuwe map naast de
  /// bron. Gooit [FileRecoveryException] als de bestemming niet aan te maken
  /// of te beschrijven is — het origineel blijft dan sowieso onaangeroerd.
  Future<FileRecoveryResult> recoverCopy(String sourceMdPath) async {
    final source = File(sourceMdPath);
    final dir = await _freshDestination(source);
    try {
      await dir.create(recursive: true);
    } catch (e) {
      throw FileRecoveryException('doelmap kon niet worden aangemaakt', e);
    }

    final quarantine = Directory(p.join(dir.path, quarantineDir));
    final members = <RecoveredMember>[];
    final diagnoses = <String>[];
    var quarantinedCount = 0;

    Future<void> take(String relPath, File src) async {
      late final List<int> bytes;
      try {
        bytes = await src.readAsBytes();
      } catch (e) {
        members.add(
          RecoveredMember(
            relPath,
            0,
            '',
            RecoveryDisposition.unreadable,
            note: 'bron niet te lezen',
          ),
        );
        diagnoses.add(
          '$relPath: de bron was niet leesbaar — niets verloren, '
          'niets gered.',
        );
        return;
      }
      final digest = sha256.convert(bytes).toString();
      final broken = _diagnose(relPath, bytes);
      final targetRel = broken == null
          ? relPath
          : p.join(quarantineDir, relPath);
      final target = File(p.join(dir.path, targetRel));
      try {
        await target.parent.create(recursive: true);
        await writeBytesAtomic(target, bytes);
      } catch (e) {
        members.add(
          RecoveredMember(
            relPath,
            bytes.length,
            digest,
            RecoveryDisposition.unreadable,
            note: 'schrijven naar de kopie mislukte',
          ),
        );
        diagnoses.add('$relPath: wegschrijven in de kopie mislukt.');
        return;
      }
      if (broken == null) {
        members.add(
          RecoveredMember(
            relPath,
            bytes.length,
            digest,
            RecoveryDisposition.copied,
          ),
        );
      } else {
        quarantinedCount++;
        members.add(
          RecoveredMember(
            relPath,
            bytes.length,
            digest,
            RecoveryDisposition.quarantined,
            note: broken,
          ),
        );
        diagnoses.add(
          '$relPath: $broken — origineel bewaard in '
          '$quarantineDir/.',
        );
      }
    }

    // Het deck zelf, dan de sidecars en projectleden die het openpad leest.
    await take(p.basename(sourceMdPath), source);
    for (final ext in _sidecarExtensions) {
      final side = File(p.setExtension(sourceMdPath, ext));
      if (await _existsQuietly(side)) {
        await take(p.basename(side.path), side);
      }
    }
    final styleFile = File(
      p.join(p.dirname(sourceMdPath), 'ocideck-style.json'),
    );
    if (await _existsQuietly(styleFile)) {
      await take('ocideck-style.json', styleFile);
    }
    for (final sub in ['logos', 'data']) {
      final subDir = Directory(p.join(p.dirname(sourceMdPath), sub));
      if (await _existsQuietly(subDir)) {
        await for (final entity in subDir.list(recursive: true)) {
          if (entity is File) {
            await take(
              p.relative(entity.path, from: p.dirname(sourceMdPath)),
              entity,
            );
          }
        }
      }
    }

    // Zegel-integriteit: is er íets veranderd aan de kopie, dan mag de kopie
    // zich niet als verzegeld voordoen.
    final sealMoved =
        quarantinedCount > 0 &&
        await _quarantineSeal(dir, quarantine, members, diagnoses);

    final (manifestPath, reportPath) = await _writeManifest(
      quarantine,
      sourceMdPath,
      dir.path,
      members,
      diagnoses,
      sealMoved,
    );

    final mdRel = p.basename(sourceMdPath);
    final md = members.where((m) => m.path == mdRel);
    return FileRecoveryResult(
      directory: dir,
      members: members,
      diagnoses: diagnoses,
      reportPath: reportPath,
      manifestPath: manifestPath,
      recoveredMarkdownPath:
          md.isNotEmpty && md.first.disposition == RecoveryDisposition.copied
          ? p.join(dir.path, mdRel)
          : null,
    );
  }

  /// Welk herstel hiervoor onderbouwd is: `null` = kopieer op zijn plek,
  /// anders de reden om het lid onder `_herstel/` te parkeren.
  String? _diagnose(String relPath, List<int> bytes) {
    if (relPath == 'ocideck-style.json') {
      try {
        ThemeProfile.fromJson(
          Map<String, Object?>.from(jsonDecode(utf8.decode(bytes)) as Map),
        );
        return null;
      } catch (e) {
        logWarning('FileRecovery: ocideck-style.json weigert', e);
        return 'stijlbestand niet te interpreteren';
      }
    }
    if (relPath.endsWith('.json') && _sidecarExtensions.any(relPath.endsWith)) {
      try {
        jsonDecode(utf8.decode(bytes));
        return null;
      } catch (e) {
        logWarning('FileRecovery: sidecar weigert', e);
        return 'sidecar bevat geen geldige JSON';
      }
    }
    return null;
  }

  Future<bool> _existsQuietly(FileSystemEntity e) async {
    try {
      return await e.exists();
    } catch (e) {
      logWarning('FileRecovery: exists() faalde', e);
      return false;
    }
  }

  /// Vrije naam naast de bron: `<stem>-herstel`, dan `-herstel-2`, … —
  /// een tweede poging overschrijft de eerste kopie nooit.
  Future<Directory> _freshDestination(File source) async {
    final stem = p.basenameWithoutExtension(source.path);
    final parent = p.dirname(source.path);
    for (var i = 1; ; i++) {
      final candidate = Directory(
        p.join(parent, i == 1 ? '$stem-herstel' : '$stem-herstel-$i'),
      );
      if (!await _existsQuietly(candidate)) return candidate;
    }
  }

  /// Manifest en rapport naast de terzijdegelegde leden: per lid pad,
  /// byte-telling en sha256 van de bron, plus de mensleesbare uitleg. Faalt
  /// dit, dan is de hele handeling niet voltooid — de aanroeper meldt dat.
  Future<(String, String)> _writeManifest(
    Directory quarantine,
    String sourceMdPath,
    String dirPath,
    List<RecoveredMember> members,
    List<String> diagnoses,
    bool sealMoved,
  ) async {
    final manifest = {
      'versie': 1,
      'bron': sourceMdPath,
      'aangemaakt': DateTime.now().toIso8601String(),
      'leden': [for (final m in members) m.toJson()],
      'diagnose': diagnoses,
      'zegelTerzijde': sealMoved,
    };
    final manifestPath = p.join(quarantine.path, 'manifest.json');
    final reportPath = p.join(quarantine.path, 'herstelrapport.md');
    try {
      await quarantine.create(recursive: true);
      await writeStringAtomic(
        File(manifestPath),
        const JsonEncoder.withIndent('  ').convert(manifest),
      );
      await writeStringAtomic(
        File(reportPath),
        _report(sourceMdPath, dirPath, members, diagnoses),
      );
    } catch (e) {
      throw FileRecoveryException('manifest of rapport niet te schrijven', e);
    }
    return (manifestPath, reportPath);
  }

  /// Legt een levend zegel terzijde wanneer de kopie afwijkt van de
  /// verzegelde bron: het zegelbestand blijft als origineel bewaard onder
  /// `_herstel/` en de kopie doet zich niet meer als verzegeld voor. Geeft
  /// terug of het zegel daadwerkelijk is verplaatst.
  Future<bool> _quarantineSeal(
    Directory dir,
    Directory quarantine,
    List<RecoveredMember> members,
    List<String> diagnoses,
  ) async {
    final seal = members.where(
      (m) =>
          m.path.endsWith('.seal.json') &&
          m.disposition == RecoveryDisposition.copied,
    );
    if (seal.isEmpty) return false;
    final sealRel = seal.first.path;
    final live = File(p.join(dir.path, sealRel));
    final target = File(p.join(quarantine.path, sealRel));
    try {
      await target.parent.create(recursive: true);
      await live.rename(target.path);
      final i = members.indexWhere((m) => m.path == sealRel);
      members[i] = RecoveredMember(
        sealRel,
        members[i].byteCount,
        members[i].sha256,
        RecoveryDisposition.quarantined,
        note: 'zegel vervalt: de kopie wijkt af van de verzegelde bron',
      );
      diagnoses.add(
        '$sealRel: de kopie wijkt af van de verzegelde bron — het zegel '
        'is terzijde gelegd en geldt hier niet meer.',
      );
      return true;
    } catch (e) {
      diagnoses.add('$sealRel: het zegel kon niet terzijde worden gelegd.');
      return false;
    }
  }

  String _report(
    String source,
    String destination,
    List<RecoveredMember> members,
    List<String> diagnoses,
  ) {
    final copied = members
        .where((m) => m.disposition == RecoveryDisposition.copied)
        .length;
    final quarantined = members
        .where((m) => m.disposition == RecoveryDisposition.quarantined)
        .length;
    final unreadable = members
        .where((m) => m.disposition == RecoveryDisposition.unreadable)
        .length;
    final b = StringBuffer()
      ..writeln('# Herstelrapport')
      ..writeln()
      ..writeln('- Bron: `$source` (ongewijzigd)')
      ..writeln('- Kopie: `$destination`')
      ..writeln('- Gemaakt: ${DateTime.now().toIso8601String()}')
      ..writeln()
      ..writeln('## Uitkomst')
      ..writeln()
      ..writeln('- $copied onderdeel(en) byte-exact meegekomen')
      ..writeln('- $quarantined onderdeel(en) terzijde in `_herstel/`')
      ..writeln('- $unreadable onderdeel(en) niet te redden')
      ..writeln();
    if (diagnoses.isNotEmpty) {
      b.writeln('## Wat er gebeurde');
      for (final d in diagnoses) {
        b.writeln('- $d');
      }
      b.writeln();
    }
    b
      ..writeln('## Onderdelen')
      ..writeln()
      ..writeln('| pad | bytes | sha256 | status |')
      ..writeln('| --- | --- | --- | --- |');
    for (final m in members) {
      b.writeln(
        '| ${m.path} | ${m.byteCount} | `${m.sha256}` | ${m.disposition.name} |',
      );
    }
    return b.toString();
  }
}

/// De herstelhandeling zelf kon niet worden voltooid — het origineel is
/// daardoor nooit kwijtgeraakt.
class FileRecoveryException implements Exception {
  final String message;
  final Object? cause;
  const FileRecoveryException(this.message, this.cause);
  @override
  String toString() => 'FileRecoveryException: $message';
}
