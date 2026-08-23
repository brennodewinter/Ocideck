// The session chat panel (SELF_ENCRYPTED_RELAY.md §6): a non-modal right rail
// shown while a realtime Matrix session runs, so co-authors can talk without
// leaving the deck. Messages are end-to-end encrypted and signed by the sender
// (`MatrixChat`); this only renders what the provider holds and sends what the
// user types.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../collab/matrix_chat.dart';
import '../../l10n/app_localizations.dart';
import '../../state/collab_session_provider.dart';
import '../../theme/app_theme.dart';
import 'slide_presence_dots.dart' show SlidePresenceDots;

/// The chat rail for the workspace row: a divider plus the panel while a Matrix
/// session runs and the user has it open, otherwise nothing. Lives here rather
/// than inline in the shell so `app_shell_main_layout.dart` stays under its size
/// ceiling — the shell just spreads the result into its row.
List<Widget> collabChatRail(WidgetRef ref) {
  final session = ref.watch(collabSessionProvider);
  final open =
      ref.watch(collabChatOpenProvider) && session.isMatrix && session.isActive;
  if (!open) return const [];
  return const [
    VerticalDivider(width: 1),
    SizedBox(width: 300, child: CollabChatPanel()),
  ];
}

class CollabChatPanel extends ConsumerStatefulWidget {
  const CollabChatPanel({super.key});

  @override
  ConsumerState<CollabChatPanel> createState() => _CollabChatPanelState();
}

class _CollabChatPanelState extends ConsumerState<CollabChatPanel> {
  final _controller = TextEditingController();
  final _focus = FocusNode(debugLabel: 'CollabChat');

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    ref.read(collabSessionProvider.notifier).sendChatMessage(text);
    _controller.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final messages = ref.watch(collabSessionProvider).chatMessages;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              Icon(Icons.forum_outlined, size: 16, color: AppTheme.slate500),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.d('Chat'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: l10n.d('Chat sluiten'),
                onPressed: () =>
                    ref.read(collabChatOpenProvider.notifier).state = false,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      l10n.d(
                        'Nog geen berichten. Zeg iets tegen je mede-auteurs.',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppTheme.slate400),
                    ),
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (_, i) =>
                      _bubble(messages[messages.length - 1 - i]),
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 13),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l10n.d('Bericht…'),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                icon: const Icon(Icons.send, size: 18),
                tooltip: l10n.d('Versturen'),
                onPressed: _send,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bubble(ChatMessage m) {
    final align = m.isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final color = m.isSelf
        ? AppTheme.accent.withValues(alpha: 0.14)
        : AppTheme.slate100;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (!m.isSelf)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: SlidePresenceDots.colorFor(m.deviceId),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    m.userId,
                    style: TextStyle(fontSize: 10, color: AppTheme.slate500),
                  ),
                ],
              ),
            ),
          Container(
            constraints: const BoxConstraints(maxWidth: 240),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(m.text, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
