import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ociserve_exam.dart';
import 'package:ocideck/services/ociserve/ociserve_exam_outbox.dart';
import 'package:ocideck/services/secret_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'exam mutation shares the encrypted outbox without losing playback',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final secrets = SecretStore(
        storage: const FlutterSecureStorage(),
        canStore: true,
      );
      const baseUrl = 'https://learn.example';
      const playback = {
        'kind': 'playback_report_v1',
        'account_id': 'participant-1',
        'organization_id': 'org',
        'snapshot': {'session_id': 'playback-1'},
      };
      await secrets.writeOciServeOutbox(baseUrl, jsonEncode([playback]));
      final outbox = OciServeExamOutbox(
        secrets: secrets,
        scope: () => const OciServeExamOutboxScope(
          baseUrl: baseUrl,
          accountId: 'participant-1',
        ),
      );
      const mutation = OciServeExamAnswerMutation(
        organizationId: 'org',
        attemptId: 'attempt-1',
        attemptItemId: 'item-1',
        answerData: {'selected_option_id': 'a'},
        challenge: 'AAAAAAAAAAAAAAAAAAAAAA',
        revision: 2,
        idempotencyKey: 'request-1',
      );

      await outbox.write(mutation);
      expect((await outbox.read('org'))?.idempotencyKey, 'request-1');
      await outbox.remove(mutation);

      final remaining =
          jsonDecode((await secrets.readOciServeOutbox(baseUrl))!) as List;
      expect(remaining, [playback]);
    },
  );
}
