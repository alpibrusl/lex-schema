# GitHub-independent parallel publishing to lex-hub

**Date:** 2026-06-07
**Status:** Design — pending review
**Scope:** `lex-schema` (and a reusable convention for any Lex project)

## Goal

Publish every release to **both** GitHub and lex-hub, in parallel, where:

- **GitHub** is a backup + public mirror (git hosting and public CI signal).
- **lex-hub** is the live registry/source we run real applications against.
- Publishing to lex-hub does **not** depend on GitHub — the GitHub Actions
  runner is no longer in the publish path.

This is the pragmatic "decouple the trigger" step. It deliberately does **not**
build the larger `lex push`/`lex pull` op-log replication feature (see
[Out of scope](#out-of-scope)).

## Background

- `lex pkg publish` (`lex-cli/src/pkg.rs`) builds a tarball and POSTs it to
  `{registry}/v1/pkg/publish` with a bearer token. The server (lex-hub) derives
  the typed op-log, type-checks, advances the branch head, and returns
  `head_op`. **The command is a plain authenticated HTTP call — it has no
  GitHub dependency.** GitHub Actions is merely where it currently runs.
- `registry = "https://hub.lexlang.org"` is already set in `lex.toml`.
- lex-vcs is op-log-native and content-addressed: writes dedup on `OpId`, so
  re-publishing the same state is idempotent (same `head_op`, no duplication).
- The repo already uses a `.githooks/` + `make hooks` convention (today: a
  `pre-commit` hook that runs `lex fmt --check` + `lex check` on staged
  `src/*.lex`).

## Design

### 1. Local publish path — `make publish`

A new `Makefile` target is the GitHub-independent publish path:

```make
publish:
	lex ci                 # check --strict + fmt --check + test + pkg install
	lex pkg publish        # tarball -> {registry}/v1/pkg/publish, auth via $LEX_PUBLISH_TOKEN
```

- Runs the full validate loop (`lex ci`) first, so a failing package can never
  be published. This is the mitigation for "publishing now originates from a
  dev machine instead of a clean CI runner."
- The token comes from the `LEX_PUBLISH_TOKEN` environment variable in the dev
  shell (see [Token handling](#4-token-handling)). No `--token` on the command
  line (avoids it landing in shell history / process listings).

### 2. Release ergonomics — `pre-push` hook

A new `.githooks/pre-push` hook publishes to lex-hub when a `v*` tag is being
pushed, so a release is a single motion:

```
git tag v0.9.3 && git push origin v0.9.3
```

→ source mirrors to GitHub **and** the hook runs `make publish` to lex-hub.

Behaviour:

- Triggers only when the push includes a ref matching `refs/tags/v*`. Ordinary
  branch pushes are untouched.
- Idempotent: lex-vcs dedups on `OpId`, so a re-pushed tag re-publishes to the
  same `head_op` harmlessly.
- Matches the existing hook style (`#!/usr/bin/env bash`, `set -euo pipefail`,
  `LEX="${LEX:-lex}"`, terse status lines).
- Skippable with `git push --no-verify` for the rare case you want to push a tag
  without publishing.

`make hooks` is extended to install **both** hooks (`pre-commit` and
`pre-push`). Hooks are per-clone, so each clone runs `make hooks` once.

### 3. GitHub workflow — CI checks only

`.github/workflows/publish.yml` is converted from *publish-to-lex-hub* to a
**CI-only** workflow (rename to `ci.yml`):

- Keeps: install the `lex` toolchain, `lex check --strict src/`, `lex fmt
  --check`, `lex test` — public verification on PRs and tags.
- Removes: the `Publish to LexHub` step and the `LEX_PUBLISH_TOKEN`
  dependency.

GitHub still validates every change publicly; it just no longer publishes.

### 4. Token handling

- `LEX_PUBLISH_TOKEN` lives only in the dev environment — a gitignored local
  env file or the shell profile — never in the repo.
- The repository secret `LEX_PUBLISH_TOKEN` on the **public** `lex-schema` repo
  is **deleted**, since Actions no longer publishes. This also closes the prior
  concern about a publish token living in a public repo.
- The token currently in use is the 1-year `alpibrusl`-tenant JWT minted on
  2026-06-07 (expires 2027-06-07). Rotation/shorter-TTL is a separate follow-up.

### 5. Reusable convention

The `make publish` target + `pre-push` hook + CI-only workflow are the standard
"publish a Lex project to lex-hub" setup, adopted the same way as the existing
`CLAUDE.md` copy pattern. Each new real application drops in the same three
pieces.

## Out of scope

- **`lex push`/`lex pull` op-log replication.** Replicating the local op-log +
  intents + attestations to lex-hub by content-address (rather than re-deriving
  ops server-side from a tarball) is the genuine "replace GitHub" step. lex-vcs's
  idempotent content-addressed design makes it natural, but it is net-new work
  in `lex-lang` + `lex-hub` and gets its own spec.
- Changing how lex-hub stores or type-checks published packages.
- Multi-tenant / multi-user publishing policy.

## Trade-offs

| Decision | Benefit | Cost |
|---|---|---|
| Publish from dev machine, not CI | No GitHub dependency; immediate | Less hermetic than a clean runner — mitigated by `lex ci` gate |
| CI-only GitHub workflow | Keeps public quality signal; kills the public secret | A second place (GitHub) still type-checks — minor duplication |
| `pre-push` tag hook | Release in one motion; familiar pattern | Per-clone install (`make hooks`); `--no-verify` escape hatch needed |

## Acceptance

- `make publish` publishes `lex-schema` to lex-hub from a dev machine with
  `LEX_PUBLISH_TOKEN` set, and prints a `head_op`.
- Pushing a `v*` tag publishes to lex-hub via the hook; pushing a branch does
  not.
- The GitHub workflow runs `lex check/fmt/test` and contains no publish step or
  token reference.
- The `LEX_PUBLISH_TOKEN` secret no longer exists on the public repo.
