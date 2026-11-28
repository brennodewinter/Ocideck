import 'package:path/path.dart' as p;

const nativeRecoveryPhases = [
  'document-crash',
  'document-restore',
  'early-crash',
  'early-reopen',
];

bool isForcedExitPhase(String phase) =>
    phase == 'document-crash' || phase == 'early-crash';

String recoveryAppSupport(String root, String phase) {
  return p.join(root, phase.startsWith('document-') ? 'document' : 'early');
}
