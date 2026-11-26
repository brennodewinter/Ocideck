#include "../../third_party/desktop_multi_window/display_selection.h"
#include <cassert>

int main() {
  assert(FindAudienceDisplay({}, "a", "b") == -1);
  assert(FindAudienceDisplay({"a"}, "a", "b") == -1);
  assert(FindAudienceDisplay({"a", "c"}, "a", "b") == -1);
  assert(FindAudienceDisplay({"b", "c"}, "a", "b") == -1);
  assert(FindAudienceDisplay({"a", "b"}, "a", "a") == -1);
  assert(FindAudienceDisplay({"a", "b", "b"}, "a", "b") == -1);
  assert(FindAudienceDisplay({"a", "b"}, "", "b") == -1);
  assert(FindAudienceDisplay({"a", "b"}, "a", "") == -1);
  assert(FindAudienceDisplay({"a", "b"}, "a", "b") == 1);
  assert(FindAudienceDisplay({"b", "a"}, "a", "b") == 0);
  assert(FindAudienceDisplay({"c", "b", "a"}, "a", "b") == 1);
}
