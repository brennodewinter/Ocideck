import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Compatibility gates for legacy security slides. MIAUW is no longer a module.
final infoSafetyProvider = Provider<InfoSafetyState>(
  (ref) => const InfoSafetyState(),
);
final infoSafetyRevealProvider = Provider<bool>((ref) => false);

class InfoSafetyState {
  const InfoSafetyState();
  bool get enabled => false;
  bool get loading => false;
  bool get revealed => false;
}
