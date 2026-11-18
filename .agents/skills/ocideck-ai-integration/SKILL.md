---
name: ocideck-ai-integration
description: Implement or review OciDeck AI-assisted drafting, model integrations and their Flutter controls while preserving provider compatibility, consent and human review. Use for OciDeck AI feature work, not general model advice.
---

# OciDeck AI integration

Work from the repository containing `pubspec.yaml`. Follow its
[AGENTS.md](../../../AGENTS.md) and [contribution guide](../../../CONTRIBUTING.md).
This skill adds application context; it does not grant permission to publish,
install global plugins, contact model services or change the user's settings.

## Find the existing boundary

- [AiClientService](../../../lib/services/ai_client_service.dart) is the shared
  `/v1/chat/completions` client. Its transport is injectable; request decoding
  validates completed assistant drafts before the consumer receives text.
- [AiSecurityGate](../../../lib/services/ai_security_gate.dart) owns the
  destination/consent decisions. Network access goes through the existing
  `network_guard` transport, including DNS pinning and redirect refusal.
- [AiSettings](../../../lib/models/ai_settings.dart) contains configuration, not
  credentials. Keys belong to `SecretStore`. Loopback identifies a destination;
  it does not establish whether a server forwards inference to a cloud model.
- [AI_ASSIST](../../../docs/design/AI_ASSIST.md) describes shipped drafting
  consumers and future app MCP work; its Flutter 3.50 assessment separates
  current changes from possible Genkit/MediaPipe adoption. Historical MIAUW
  references are not instructions to restore that removed module.

## Preserve draft semantics

Use `AiClientService` for new drafting consumers. Keep AI optional, preserve
existing consent decisions and the human's existing text when a request fails.
Do not turn provider tool calls into editor actions or execute generated code.
Explicit refusals, incomplete completions and malformed envelopes are errors;
an empty completed answer can be an intentional abstention. Older compatible
servers may omit the completion reason. Keep provider payloads out of errors
and logs, and do not add automatic retries of prompts/images.

Keep domain parsers deterministic: translation preserves IDs/structure;
condensing preserves the original in notes; image suggestions use the existing
image-egress consent and bounded resize path. Meeting media has a separate
consent domain. Test the consumer's contract rather than treating prompt text
as an enforcement boundary.

## Develop and verify

Use the Dart bundled with the pinned Flutter SDK. If the client offers Dart MCP
tools, use their diagnostics, symbols and widget inspection for the task. Hot
reload/restart only a development app you launched or the user identified for
this work; avoid restarting an unrelated app with unsaved work. The SDK command
`dart mcp-server` is development tooling, not an OciDeck app MCP endpoint and not
an inference backend. Keep protocol logging off for ordinary work.

Use fake `AiHttpTransport` responses to verify protocol behavior without sending
user documents to a model. Relevant regression tests:

```sh
flutter test test/ai_backend_test.dart test/ai_suggest_control_test.dart
flutter test test/ai_translate_service_test.dart test/ai_condense_service_test.dart
flutter test test/image_alt_ai_service_test.dart
```

Include the changed consumer's tests and follow the contribution guide's
pre-merge gate. For browser changes, retain WASM/JS conditional imports and run
`make check-web`; the existing web release probes cover renderer startup. A
successful build or fake transport test is not a model-quality benchmark.
