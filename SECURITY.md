# Security Policy

## Reporting a vulnerability

**Please do not report security vulnerabilities through public GitHub issues,
discussions, or pull requests.**

Instead, report them privately via GitHub's **"Report a vulnerability"** button
under the repository's **Security** tab (Security Advisories). If that is not
available to you, contact the maintainer directly and wait for a reply before
disclosing anything publicly.

When reporting, please include as much of the following as you can:

- A description of the issue and its impact.
- Steps to reproduce (a minimal deck or input file if relevant).
- The OciDeck version, operating system, and Flutter version.
- Any proof-of-concept, logs, or screenshots.

## What to expect

- **Acknowledgement** of your report as quickly as we reasonably can.
- An assessment and, where confirmed, a fix developed under coordinated
  (responsible) disclosure.
- Credit for the discovery if you wish — let us know how you would like to be
  named.

We ask that you give us a reasonable opportunity to address the issue before any
public disclosure, and that you avoid privacy violations, data destruction, or
service disruption while researching.

## Scope notes

OciDeck is an offline desktop application. Areas of particular interest:

- Parsing of untrusted decks (`.md`), packages (`.ocideck`), sidecars
  (`.ink.json`, captions), and linked CSV data.
- Importing presentations from a URL.
- The HTML export, which inlines third-party JavaScript (marked, highlight.js,
  mermaid, MathJax) to render offline.
- The export classification gate (`ClassificationPolicy`) — any way to export a
  deck classified above the configured release ceiling.

## Supported versions

Security fixes target the latest released version and the default development
branch. Older versions may not receive fixes.
