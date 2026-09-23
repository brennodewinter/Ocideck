# Modifications to markdown_quill

Forked from [TarekkMA/markdown_quill](https://github.com/TarekkMA/markdown_quill) 4.3.0 (MIT).

Reason: the published package is 17 months stale, has an unverified publisher,
and issue creation is restricted on the upstream repo. OciDeck depends on this
package for the WYSIWYG editor's markdown↔Quill bridge — core functionality.
Vendoring gives us control over bug fixes and compatibility with future
`flutter_quill` releases. See issue #1743 for the full evaluation.

## Changes from upstream 4.3.0

1. **Removed `charcode` dependency.** `embeddable_table_syntax.dart` used
   `package:charcode` for three ASCII code-unit constants (`$pipe`, `$space`,
   `$tab`). Replaced with local `const int` definitions. This drops a
   transitive dependency that served no other purpose.

2. **Removed `charcode` from `pubspec.yaml`.** Only `collection`,
   `flutter_quill`, and `markdown` remain as dependencies.

3. **Fixed lint issues for OciDeck's `--fatal-infos` analyzer.** Removed
   unnecessary library name (`markdown_quill.dart`), added `const` to
   `CodeBlockLanguageAttribute` constructor, renamed local variables
   `_leadingSpacesPattern`/`_softLineBreak` to avoid leading underscores.

4. **Preserved `h4`–`h6` headings.** Upstream's `_elementToBlockAttr` mapped
   only `h1`–`h3`; a `####` heading silently became a plain paragraph and the
   level was lost on the next save. Added `h4`/`h5`/`h6` → `Attribute.h4`/`h5`/`h6`.

5. **Task-list checkbox survives loose lists.** The `li` handler read
   `element.children!.first` as the `<input>` checkbox, but `package:markdown`
   nests the checkbox inside the `<p>` child when a list is loose (blank line
   between items) — so `- [x]` read back as unchecked. The handler now finds
   the `input` element anywhere in the item subtree
   (`_firstDescendantWithTag`).
