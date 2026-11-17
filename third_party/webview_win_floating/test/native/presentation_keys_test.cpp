#include "../../windows/presentation_keys.h"
#include <cstdlib>
#include <iostream>
void check(bool value) { if (!value) std::exit(1); }
int main() {
  for (const auto key : {0x25u, 0x27u, 0x21u, 0x22u, 0x1bu, 0x24u, 0x23u}) {
    check(!PresentationKey(false, key, true, false).handled);
    const auto first = PresentationKey(true, key, true, false);
    check(first.handled && first.dispatch);
    const auto held = PresentationKey(true, key, true, true);
    check(held.handled && !held.dispatch);
    const auto up = PresentationKey(true, key, false, true);
    check(up.handled && !up.dispatch);
    check(!PresentationKey(false, key, false, true).handled);
    // A separate physical press must navigate again.
    check(PresentationKey(true, key, true, false).dispatch);
  }
  for (const auto key : {0x20u, 0x41u, 0x09u, 0x26u, 0x28u}) {
    check(!PresentationKey(true, key, true, false).handled);
  }
  std::cout << "native presentation key filtering: passed\n";
}
