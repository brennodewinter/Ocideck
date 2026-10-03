// De controle door de maker (FORM_INTAKE.md §7.4), de kant met bestanden: het hoofdstuk
// van één inzending en het adres waaraan het gaat.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/form/form_book.dart';
import 'package:ocideck/services/form/form_maker_check.dart';
import 'package:ocideck/services/form/form_submission_actions.dart';
import 'package:ocideck/services/form/form_workspace.dart';
import 'package:path/path.dart' as p;

import 'support/form_maker_check_fixtures.dart';
import 'support/temp_dir.dart';

const String template = '# {naam}\n\n{mail}';

void main() {
  late Directory dir;
  late FormWorkspace workspace;
  final now = DateTime.utc(2026, 11, 3);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ocideck_makercheck_');
    workspace = FormWorkspace(p.join(dir.path, 'werkmap'));
    await workspace.publishForm(kookWithMail);
  });
  tearDown(() => deleteTempDir(dir));

  Future<void> land(
    int n, {
    String naam = 'Sari',
    String mail = 'sari@example.nl',
    String status = 'received',
    bool withdrawn = false,
  }) => landKook(
    workspace,
    n,
    naam: naam,
    mail: mail,
    status: status,
    withdrawn: withdrawn,
  );

  Future<FormMakerCheckOutcome> prepare(int n, {String t = template}) =>
      prepareMakerCheck(workspace, sid: sidOf(n), template: t, now: now);

  File check([String name = 'check-abcdefgh']) =>
      File(p.join(workspace.root, 'book', '$name.md'));

  group('prepareMakerCheck', () {
    test('maakt het hoofdstuk van die ene inzending, met haar adres', () async {
      await land(0);
      await land(1, naam: 'Joe', mail: 'joe@example.nl');
      final outcome = await prepare(0) as FormMakerCheckReady;
      expect(outcome.address, 'sari@example.nl');
      expect(outcome.path, check().path);
      final text = await check().readAsString();
      expect(text, contains('# Sari'));
      expect(text, isNot(contains('Joe')));
    });

    test('welke status ze ook heeft', () async {
      await land(0, status: 'maker-approved');
      expect(await prepare(0), isA<FormMakerCheckReady>());
    });

    test('het adres is leeg als de maker er geen opgaf', () async {
      await land(0, mail: '');
      final outcome = await prepare(0) as FormMakerCheckReady;
      expect(outcome.address, isNull);
    });

    test(
      'een tweede keer geeft een nieuw document, nooit een overschreven',
      () async {
        await land(0);
        final first = await prepare(0) as FormMakerCheckReady;
        await check().writeAsString('al verstuurd');
        final second = await prepare(0) as FormMakerCheckReady;
        final third = await prepare(0) as FormMakerCheckReady;
        expect(p.basename(first.path), 'check-abcdefgh.md');
        expect(p.basename(second.path), 'check-abcdefgh-2.md');
        expect(p.basename(third.path), 'check-abcdefgh-3.md');
        expect(await check().readAsString(), 'al verstuurd');
      },
    );

    test('bij het honderdste document is het op', () async {
      await land(0);
      final dirBook = Directory(p.join(workspace.root, 'book'))
        ..createSync(recursive: true);
      File(p.join(dirBook.path, 'check-abcdefgh.md')).writeAsStringSync('x');
      for (var n = 2; n <= 99; n++) {
        File(
          p.join(dirBook.path, 'check-abcdefgh-$n.md'),
        ).writeAsStringSync('x');
      }
      final outcome = await prepare(0) as FormMakerCheckRefused;
      expect(outcome.outcome, isA<FormBookNameTaken>());
    });

    test('het laatste vrije nummer is het negenennegentigste', () async {
      await land(0);
      final dirBook = Directory(p.join(workspace.root, 'book'))
        ..createSync(recursive: true);
      File(p.join(dirBook.path, 'check-abcdefgh.md')).writeAsStringSync('x');
      for (var n = 2; n <= 98; n++) {
        File(
          p.join(dirBook.path, 'check-abcdefgh-$n.md'),
        ).writeAsStringSync('x');
      }
      final outcome = await prepare(0) as FormMakerCheckReady;
      expect(p.basename(outcome.path), 'check-abcdefgh-99.md');
    });

    test('een ingetrokken inzending krijgt geen hoofdstuk', () async {
      await land(0, withdrawn: true);
      final outcome = await prepare(0) as FormMakerCheckRefused;
      expect((outcome.outcome as FormBookEmpty).withdrawn, 1);
      expect(check().existsSync(), isFalse);
    });

    test('een inzending die er niet is', () async {
      expect(await prepare(0), isA<FormMakerCheckUnavailable>());
    });

    test('een verwijderde inzending', () async {
      await land(0);
      await deleteSubmission(workspace, sidOf(0));
      expect(await prepare(0), isA<FormMakerCheckUnavailable>());
    });

    test('een sjabloon met een onbekend veld wordt geweigerd', () async {
      await land(0);
      final outcome =
          await prepare(0, t: '# {naam} {fout}') as FormMakerCheckRefused;
      expect((outcome.outcome as FormBookUnknownFields).ids, ['fout']);
      expect(check().existsSync(), isFalse);
    });
  });

  group('zonder formulier in de werkmap', () {
    Future<void> unpublish() =>
        Directory(p.join(workspace.root, 'forms')).delete(recursive: true);

    test('is er geen hoofdstuk te maken', () async {
      await land(0);
      await unpublish();
      expect(await prepare(0), isA<FormMakerCheckUnavailable>());
    });

    test('is er geen adres te vinden', () async {
      await land(0);
      await unpublish();
      expect(await makerAddressOfSubmission(workspace, sidOf(0)), isNull);
    });
  });

  group('makerAddressOfSubmission', () {
    test('is het adres in de inzending', () async {
      await land(0);
      expect(
        await makerAddressOfSubmission(workspace, sidOf(0)),
        'sari@example.nl',
      );
    });

    test('is leeg zonder adres', () async {
      await land(0, mail: '');
      expect(await makerAddressOfSubmission(workspace, sidOf(0)), isNull);
    });

    test('is leeg voor een inzending die er niet is', () async {
      expect(await makerAddressOfSubmission(workspace, sidOf(5)), isNull);
    });

    test('is leeg voor een verwijderde inzending', () async {
      await land(0);
      await deleteSubmission(workspace, sidOf(0));
      expect(await makerAddressOfSubmission(workspace, sidOf(0)), isNull);
    });
  });
}
