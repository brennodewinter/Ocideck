import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import 'ociserve_exam_dialog.dart';

List<Widget> ociServeExamActions(String? organizationId, bool compact) =>
    organizationId == null
    ? const []
    : [OciServeExamButton(organizationId: organizationId, compact: compact)];

class OciServeExamButton extends StatelessWidget {
  const OciServeExamButton({
    super.key,
    required this.organizationId,
    required this.compact,
  });

  final String organizationId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    void open() =>
        OciServeExamDialog.show(context, organizationId: organizationId);
    if (compact) {
      return IconButton(
        key: const Key('ociserve-exams-button'),
        tooltip: context.l10n.d('Mijn examens'),
        onPressed: open,
        icon: const Icon(Icons.assignment_outlined),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: OutlinedButton.icon(
        key: const Key('ociserve-exams-button'),
        onPressed: open,
        icon: const Icon(Icons.assignment_outlined),
        label: Text(context.l10n.d('Mijn examens')),
      ),
    );
  }
}
