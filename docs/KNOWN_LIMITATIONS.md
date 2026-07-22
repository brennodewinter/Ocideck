# OciDeck — Known limitations

> **Status:** current-state list of what is not there yet · **Status last reviewed:** 2026-07-22 · **Published by:** Stichting LibreKAT

This page exists so you do not have to assemble it yourself. Every item below
was already written down somewhere in this repository; they were spread across
five documents, which meant a reader met them one surprise at a time. Nothing
here is new — the pointers say where the full account lives.

For an alpha, this list is a feature. Read it before you decide whether OciDeck
fits what you are doing.

## Nothing is released

No version has ever been tagged, no signed build is published, and there is no
installer or download page. The only way to run OciDeck is to build it from
source with the pinned Flutter toolchain. → [BUILD.md](BUILD.md),
[FAQ.md](FAQ.md#is-ocideck-free-to-use)

## The exports are pictures, not documents

PDF and PPTX are one bitmap per slide: no text layer, no alt-text, no reading
order, no selectable text. Hand over the Markdown or the HTML export when the
recipient needs to *read* rather than *look*. No WCAG conformance is claimed,
and nothing has been tested with a real screen reader. →
[ACCESSIBILITY.md](ACCESSIBILITY.md)

## Left-to-right only

The interface and the slide canvas are left-to-right. None of the 32 interface
languages is right-to-left, and no direction-sensitive layout primitives are in
use. This also governs your *content*: an Arabic or Hebrew paragraph on a slide
gets the wrong base direction. → [ACCESSIBILITY.md](ACCESSIBILITY.md)

## The translations have not been reviewed

Roughly 71,500 translations across 32 languages, produced during AI-assisted
development and never reviewed word by word by a native speaker. A build gate
catches a *missing* string, not a wrong one. Separately, about fifty field
labels in the slide editors and a handful of blocking messages still show their
Dutch source text whatever your language setting. →
[README.md](../README.md#contributing)

## The web build does less than the desktop build

No local video, no local CVE database, no WebDAV browsing, and a URL import that
the browser blocks on CORS grounds is retried through a proxy on the host that
served the app — so that host sees the address you typed. The first visit
downloads a large bundle. → [HOSTING.md](HOSTING.md), section *Web build
limitations to communicate*

## Marp CLI compatibility is unverified

The saved `.md` is designed to be processed by the Marp CLI and the VS Code Marp
extension. That has not been tested against the real tools — there is no Node
tooling in this repository and no test that runs one. →
[FILE_FORMAT.md](FILE_FORMAT.md)

## Much of it has never met a real server

A worklist of what is built, passes its own tests, and has never been exercised
against a real forge, a second operating system or a real report is kept
deliberately. It is in Dutch. →
[design/VERIFICATION.md](design/VERIFICATION.md)

## The privacy check is an aid, not a guarantee

It reduces the chance that personal data leaks out unintentionally. It does not
promise that everything is found, and image scanning cannot see what a
photograph is *of*. → [PRIVACY.md](PRIVACY.md),
[USER_GUIDE.md](USER_GUIDE.md#privacy-check)

## There are no screenshots

A tool whose entire purpose is visual currently documents itself in prose only.

---

*This page replaces the roadmap section that used to sit in
[FAQ.md](FAQ.md) — a roadmap nobody maintains is worse than none. What is
planned is decided in the issue tracker, in the open.*
