/// Expands common Marp/GitHub emoji shortcodes locally.
///
/// The replacement is deliberately Unicode-only: no CDN, network request or
/// additional package is needed to preview or export a deck.
String expandMarpEmojiShortcodes(String source) => source.replaceAllMapped(
  _emojiShortcode,
  (match) => _marpEmoji[match.group(1)] ?? match.group(0)!,
);

final _emojiShortcode = RegExp(r'(?<![\w:]):([a-z0-9_+\-]+):(?!:)');

const _marpEmoji = <String, String>{
  '+1': '👍',
  '-1': '👎',
  '100': '💯',
  'bulb': '💡',
  'checkered_flag': '🏁',
  'clap': '👏',
  'eyes': '👀',
  'fire': '🔥',
  'globe_with_meridians': '🌐',
  'green_heart': '💚',
  'heart': '❤️',
  'heavy_check_mark': '✔️',
  'information_source': 'ℹ️',
  'key': '🔑',
  'lock': '🔒',
  'mag': '🔍',
  'memo': '📝',
  'no_entry': '⛔',
  'ok_hand': '👌',
  'package': '📦',
  'rocket': '🚀',
  'shield': '🛡️',
  'smile': '😄',
  'sparkles': '✨',
  'star': '⭐',
  'tada': '🎉',
  'thinking': '🤔',
  'thumbsup': '👍',
  'warning': '⚠️',
  'wave': '👋',
  'white_check_mark': '✅',
  'x': '❌',
  'zap': '⚡',
};
