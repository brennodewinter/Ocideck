import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/slide_quality.dart';
import '../state/editor_provider.dart';
import '../widgets/dialogs/settings_dialog.dart';

/// Navigate from a quality issue to the relevant editor field or theme colour.
void navigateToSlideQualityIssue({
  required BuildContext context,
  required WidgetRef ref,
  required SlideQualityIssue issue,
}) {
  if (issue.isDeckWide) {
    SettingsDialog.show(
      context,
      initialSection: SettingsSection.presentation,
      highlightThemeField: issue.field,
    );
    return;
  }
  ref
      .read(editorProvider.notifier)
      .selectWithQualityField(issue.slideIndex, issue.field);
}
