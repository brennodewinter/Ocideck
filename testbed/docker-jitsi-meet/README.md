# Prosody testbed for OciDeck's XMPP integration test

A local [Prosody](https://prosody.im/) XMPP server for testing OciDeck's XMPP
collaboration transport against a real server. Used by
`test/xmpp/xmpp_docker_jitsi_integration_test.dart`
(design doc `docs/design/XMPP_COLLAB_TRANSPORT.md` §8, §11 stap 8).

## Setup

```sh
cd testbed/docker-jitsi-meet
cp .env.example .env
docker compose up -d
```

That's it — no post-start patching needed. The config is mounted read-only
from `prosody.cfg.lua`, which has anonymous auth, MUC with no room creation
restrictions, and WebSocket enabled.

## What the test connects to

- **WebSocket endpoint:** `ws://127.0.0.1:5280/xmpp-websocket`
- **XMPP domain:** `meet.jitsi` (set via `domainOverride` on `XmppSettings`)
- **MUC domain:** `conference.meet.jitsi`
- **Auth:** anonymous (SASL ANONYMOUS, no accounts needed)

The `ws://` scheme is only allowed to a literal loopback address
(`127.0.0.1`) — the connection layer enforces this. `trustedInternal: true`
on `XmppSettings` lets NetGuard resolve the loopback address.

## Running the integration test

```sh
make test-xmpp-integration
```

The test is gated behind the `OCIDECK_XMPP_INTEGRATION` environment variable —
it is skipped unless the Prosody stack is running. `make check` does not run it.

## Why not docker-jitsi-meet?

The full `docker-jitsi-meet` stack (with Jitsi's custom Prosody modules) was
tried first but has several issues for integration testing:
- `restrict_room_creation` is hardcoded `true` and the config is regenerated
  on every restart, so patches are lost.
- `c2s_require_encryption = true` is forced by the entrypoint script.
- The `muc_domain_mapper` and `muc_resource_validate` modules add Jitsi-
  specific JID rewriting and nick validation that interfere with non-Jitsi
  clients.
- The `muc_hide_all` module is referenced in the config but doesn't exist
  on the filesystem.

A plain Prosody with a simple config avoids all of these issues and still
exercises the full XMPP-over-WebSocket transport (SASL, bind, MUC, presence,
messages) that OciDeck uses.
