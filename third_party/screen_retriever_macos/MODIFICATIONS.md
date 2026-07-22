# Modifications to `screen_retriever_macos`

This directory is a **modified copy** of the `screen_retriever_macos` package by
LiJianying, licensed under the **MIT License** (see [`LICENSE`](LICENSE),
© 2022-2024 LiJianying). MIT carries no modification-notice duty, but the same
record is kept here as for the Apache-2.0 fork next door — a reader should not
have to diff a tarball to learn what we changed.

**Upstream:** <https://github.com/leanflutter/screen_retriever>
**Branched from commit:** `ed1e52204d75b69330fb4b0e0b8d4d57e3c53833`
(2024-08-18, `packages/screen_retriever_macos`), package version 0.2.0.
**Modified by:** the OciDeck project (Brenno de Winter), from 2026-06-05.

Every file taken from upstream is byte-identical to that commit. Nothing was
edited; two files were **added**.

## Why the fork exists

Recent Xcode/CocoaPods versions build the macOS plugin through Swift Package
Manager, which expects sources under `Sources/<target>/`. The upstream 0.2.0
layout only has the CocoaPods `Classes/` tree, so the plugin failed to build.

## What was added

| File | Change |
| --- | --- |
| `macos/screen_retriever_macos/Package.swift` | Added a Swift Package manifest (`swift-tools-version: 5.9`, macOS 10.15) so the plugin resolves under SPM. |
| `macos/screen_retriever_macos/Sources/screen_retriever_macos/ScreenRetrieverMacosPlugin.swift` | Added the SPM-layout copy of the plugin source. Byte-identical to upstream's `macos/Classes/ScreenRetrieverMacosPlugin.swift`, which is kept for the CocoaPods path. |

## Keeping it honest

`tool/sbom_build.dart` records the upstream URL, this commit and a SHA-256 tree
hash of this directory in the SBOM; `make sbom-verify` recomputes the hash.

Upstream has since gained SPM support of its own (0.2.1+). When this fork is
bumped, check whether it can be dropped entirely.
