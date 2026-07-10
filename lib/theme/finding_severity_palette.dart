import 'package:flutter/material.dart';

import '../services/cvss/cvss4.dart';
import 'app_theme.dart';

/// Severity → colour tokens for finding cards and CVSS badges, following the
/// FIRST rating bands (PENTEST_MIAUW §11). Backed by the deterministic `const`
/// [AppTheme] severity tokens (no theme lookup), so a finding renders identically
/// in the on-screen preview and in a headless export isolate. A local mapping for
/// P1-FIND; P1-THEME folds severity into the security [ThemeProfile].
abstract final class FindingSeverityPalette {
  /// The band colour for [severity]; the neutral tone for an unset/absent one.
  static Color of(Cvss4Severity? severity) => switch (severity) {
    Cvss4Severity.critical => AppTheme.severityCritical,
    Cvss4Severity.high => AppTheme.severityHigh,
    Cvss4Severity.medium => AppTheme.severityMedium,
    Cvss4Severity.low => AppTheme.severityLow,
    Cvss4Severity.none => AppTheme.severityNone,
    null => AppTheme.severityNone,
  };
}
