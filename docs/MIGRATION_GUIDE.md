# OciDeck — Migration Guide

## There is nothing to migrate between yet

OciDeck has **never tagged a release**. `git tag` is empty, `pubspec.yaml` says
`0.2.0+1`, and there is no versioning or release scheme. There are no numbered
versions, so there are no migration paths between them, no release notes, and no
conversion tooling.

Until that changes, this document records only what is true today: what the app
migrates on its own, and the rules that migration follows.

> An earlier version of this guide described migrations from "1.x to 2.x" and
> "2.x to 3.x", automated file-format converters, theme-profile migration tools,
> and community support forums. None of those existed. The guide was generated
> boilerplate; it is replaced here with the real picture. Corrected 2026-07-19.

## What does migrate: stored settings

Deck files and theme profiles need no migration — see below. What does change
shape between builds is the app's own stored settings, in `SharedPreferences`.
Those migrations run silently at startup; a user never sees them and has nothing
to do.

The one that exists today is in
`lib/state/parts/settings_provider_connections.dart`: the old separate `libraries`, `homeDirectory`, `webdavServer` and `gitRepo` keys
are folded into one ordered `storageConnections` list. Libraries come first in
their existing order, then WebDAV, then git — so whatever was the default before
is still the default after.

## The rules these migrations follow

These are the conventions to keep to when you add the next one. They are the
reason the code looks the way it does, and they are not obvious from reading it.

**Migrate on read, persist on first write.** `_loadConnections` computes the
migrated list but does not save it. The legacy keys stay on disk until the user
actually changes something. That is what makes downgrading to an older build
safe for anyone who has not touched the settings yet.

**An emptied list is a decision, not an absence.** If the new key exists but
holds nothing, the user deleted everything. Migrating again would resurrect it
at every launch. Distinguish "key missing" from "key empty".

**Never rename a persisted key just to tidy up.** The info-safety module's key
is still `secModuleEnabled` even though every identifier around it was renamed —
see `lib/state/info_safety_provider.dart`. Renaming it would flip the toggle off for everyone who had switched it on, and
nobody would report it, because it looks exactly like the module was never
enabled. If you want the names aligned, write the migration that reads the old
key first.

**Pick defaults that preserve the old meaning.** `WebdavServer.kind` defaults to
`nextcloud` because Nextcloud was the only option before other servers were
supported. Stored records that predate the field therefore keep working without
any migration at all. A default chosen this way is cheaper than a migration.

**Remove orphan keys on load.** When a feature is dropped, its key should be
deleted when encountered, so an upgraded install does not carry it forever.

## Deck files and theme profiles

Deck `.md` files and `.ocideckstyle` profiles carry no format version, and there
are no converters. Format changes so far have been additive: new front-matter
fields that older builds ignore and newer builds default. An older deck opens in
a newer build.

This holds only as long as changes stay additive. The first change that does not
is the point at which this project needs a real format version and a real
migration path — and that decision belongs in
[FILE_FORMAT.md](FILE_FORMAT.md), documented before it ships, not after.

## When there is a release scheme

Once versions are actually tagged, this document becomes the place to record,
per release: what breaks, what the user must do, and how to go back. Written at
the time the breaking change lands, not reconstructed later.

Bugs and questions go to the project's issue tracker (Forgejo). There is no
community forum, no support channel, and no mailing list.
