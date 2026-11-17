#pragma once

struct PresentationKeyDecision { bool handled; bool dispatch; };
inline PresentationKeyDecision PresentationKey(bool enabled, unsigned key,
                                              bool key_down, bool was_down) {
  const bool reserved = key == 0x25 || key == 0x27 || key == 0x21 ||
                        key == 0x22 || key == 0x1b || key == 0x24 || key == 0x23;
  const bool handled = enabled && reserved;
  return {handled, handled && key_down && !was_down};
}
