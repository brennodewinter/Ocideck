import 'package:flutter_riverpod/legacy.dart';

import '../services/markdown_transfer_bridge.dart';

/// De aangeboden Markdown-overdracht waarop de shell de toestemmingsvraag
/// toont (#2827). `null` = niets openstaand. De bridge zet hem, de shell
/// maakt hem leeg zodra de vraag getoond is — zelfde patroon als
/// [importSecurityAlarmProvider].
final inboundMarkdownRequestProvider = StateProvider<InboundMarkdownRequest?>(
  (ref) => null,
);
