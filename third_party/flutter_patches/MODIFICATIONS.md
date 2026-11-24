# Flutter macOS accessibility backport

Upstream: Flutter framework commit
`b304cf18b6864d141cf08e26a07898901cddb4b5` (Flutter #193372).
Licence: BSD-3-Clause; the upstream copyright and licence are retained in LICENSE.

The patch is an unmodified upstream git-format patch. OciDeck applies it to
Flutter 3.50.0, revision `ab2912035e160d9cad6306df307576da6128ebdb`, only for the
macOS release build through `scripts/with_macos_flutter_semantics_fix.sh`.
The wrapper locks the SDK, checks its revision and reverses the patch on exit.

The change prevents traversal-child semantics nodes without a traversal parent
from reaching the native accessibility bridge and keeps their dirty state in
sync when the parent changes. OciDeck makes no additional edits to the patch.
Remove this backport when the pinned Flutter SDK includes the upstream fix.
