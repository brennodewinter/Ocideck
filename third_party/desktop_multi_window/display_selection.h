// NOTICE: This file was added by the OciDeck project.
// Original package: desktop_multi_window (c) 2021 Mixin, Apache License 2.0
// (see LICENSE). Modification notice per Apache-2.0 section 4(b);
// see MODIFICATIONS.md.
#pragma once
#include <algorithm>
#include <string>
#include <unordered_set>
#include <vector>

// Identity lookup only: no fallback to a new interpretation of an old index.
inline int FindAudienceDisplay(const std::vector<std::string>& identities,
                               const std::string& presenter,
                               const std::string& target) {
  if (identities.size() < 2 || presenter.empty() || target.empty() ||
      presenter == target ||
      std::unordered_set<std::string>(identities.begin(), identities.end()).size()
          != identities.size() ||
      std::find(identities.begin(), identities.end(), presenter) == identities.end()) {
    return -1;
  }
  auto found = std::find(identities.begin(), identities.end(), target);
  return found == identities.end() ? -1 : static_cast<int>(found - identities.begin());
}
