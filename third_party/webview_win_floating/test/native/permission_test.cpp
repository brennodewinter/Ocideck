#include "../../windows/pending_permissions.h"
#include <cstdlib>
#include <iostream>
#include <vector>

void check(bool condition) {
  if (!condition) {
    std::cerr << "permission ownership contract failed\n";
    std::exit(1);
  }
}
int main() {
  std::vector<bool> completed;
  auto record = [&](bool granted) { completed.push_back(granted); };
  {
    PendingPermissions pending;
    const auto first = pending.Add(record);
    pending.Respond(first, true);
    pending.Respond(first, false);
    pending.Respond(99999, true);
    check(completed == std::vector<bool>{true});
    const auto stale = pending.Add(record);
    pending.Add(record);
    pending.CancelAll(); // Navigation owns cancellation, not a late Dart reply.
    pending.Respond(stale, true);
    check(completed == (std::vector<bool>{true, false, false}));
    pending.Add([&](bool granted) {
      record(granted);
      pending.Add(record); // Reentrant request belongs to the next document.
    });
    pending.CancelAll();
    check(completed.size() == 4);
    pending.Close();
    check(completed == (std::vector<bool>{true, false, false, false, false}));
    check(pending.Add(record) == 0); // Closed native owner denies immediately.
    pending.Close();
    check(completed.size() == 6);
  }
  check(completed.size() == 6);
  {
    PendingPermissions pending;
    pending.Add(record);
  } // Disposal completes unanswered deferrals.
  check(completed.size() == 7 && !completed.back());
  std::cout << "permission deferral ownership: passed\n";
}
