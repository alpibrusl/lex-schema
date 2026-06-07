# GitHub-independent parallel publishing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `lex-schema`'s publish-to-lex-hub off GitHub Actions onto a local `make publish` + `pre-push` tag hook, leaving GitHub as a CI-only backup/mirror.

**Architecture:** `lex pkg publish` is already a plain authenticated HTTP call to the registry, so "decoupling from GitHub" is purely a matter of where it runs. We add a Makefile target and a `pre-push` git hook as the local publish path, convert the publish workflow to CI-only, and delete the now-unused repo secret.

**Tech Stack:** GNU Make, bash git hooks, GitHub Actions YAML, the `lex` CLI.

Spec: `docs/superpowers/specs/2026-06-07-github-independent-publish-design.md`

All work happens in the `lex-schema` repo on branch `chore/local-publish`.

---

### Task 1: Add `make publish` and install both hooks in `make hooks`

**Files:**
- Modify: `/home/alpibru/workspace/alpibrusl/lex-schema/Makefile`

- [ ] **Step 1: Replace the Makefile with the publish target + both-hooks install**

Current Makefile only installs the `pre-commit` hook. Replace its full contents with:

```make
.PHONY: hooks publish

# Install git hooks into this clone (run once per clone).
hooks:
	mkdir -p .git/hooks
	cp .githooks/pre-commit .git/hooks/pre-commit
	cp .githooks/pre-push   .git/hooks/pre-push
	chmod +x .git/hooks/pre-commit .git/hooks/pre-push
	@echo "hooks installed (pre-commit, pre-push) — run 'make hooks' in each clone"

# Publish this package to the registry in lex.toml (lex-hub).
# GitHub-independent: runs the full validate loop, then publishes using
# LEX_PUBLISH_TOKEN from the environment.
publish:
	@test -n "$$LEX_PUBLISH_TOKEN" || { echo "LEX_PUBLISH_TOKEN not set in environment"; exit 1; }
	lex ci
	lex pkg publish
```

- [ ] **Step 2: Verify the Makefile parses and the guard works**

Run: `cd /home/alpibru/workspace/alpibrusl/lex-schema && make -n publish`
Expected: prints the recipe lines (the `test -n` guard, `lex ci`, `lex pkg publish`) with no "missing separator" / parse errors.

Run (guard fires when token unset): `cd /home/alpibru/workspace/alpibrusl/lex-schema && env -u LEX_PUBLISH_TOKEN make publish`
Expected: FAIL fast with `LEX_PUBLISH_TOKEN not set in environment` (exit 1), before any `lex` call.

- [ ] **Step 3: Commit**

```bash
cd /home/alpibru/workspace/alpibrusl/lex-schema
git add Makefile
git commit -m "build: add 'make publish' and install pre-push hook via 'make hooks'"
```

---

### Task 2: Add the `pre-push` hook

**Files:**
- Create: `/home/alpibru/workspace/alpibrusl/lex-schema/.githooks/pre-push`

- [ ] **Step 1: Write the hook**

git invokes `pre-push` with remote name + URL as args and feeds
`<local ref> <local sha> <remote ref> <remote sha>` lines on stdin. We publish
only when a pushed ref is an annotated/lightweight tag matching `refs/tags/v*`.
Style matches the existing `pre-commit` hook.

Create `.githooks/pre-push` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Publish to lex-hub when a v* tag is being pushed. Other pushes are untouched.
# Skip entirely with `git push --no-verify`.

publish_tag=""
while read -r local_ref _local_sha _remote_ref _remote_sha; do
  case "$local_ref" in
    refs/tags/v*) publish_tag="${local_ref#refs/tags/}" ;;
  esac
done

if [ -z "$publish_tag" ]; then
  exit 0
fi

echo "[pre-push] tag $publish_tag → publishing to lex-hub"
if [ -z "${LEX_PUBLISH_TOKEN:-}" ]; then
  echo "[pre-push] LEX_PUBLISH_TOKEN not set — cannot publish."
  echo "           set it, or re-run with: git push --no-verify"
  exit 1
fi

make publish
echo "[pre-push] published $publish_tag"
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x /home/alpibru/workspace/alpibrusl/lex-schema/.githooks/pre-push`
Expected: no output; `ls -l` shows the `x` bits.

- [ ] **Step 3: Test the tag-detection logic in isolation (no real push)**

The hook reads refs from stdin. Verify a tag ref is detected and a branch ref is not, without invoking `make publish` (we stub the decision by checking the parse).

Run (tag → should reach the token check, NOT exit 0 early):
```bash
cd /home/alpibru/workspace/alpibrusl/lex-schema
printf 'refs/tags/v9.9.9 abc refs/tags/v9.9.9 0000\n' | env -u LEX_PUBLISH_TOKEN bash .githooks/pre-push; echo "exit=$?"
```
Expected: prints `[pre-push] tag v9.9.9 → publishing to lex-hub` then the `LEX_PUBLISH_TOKEN not set` message, `exit=1`.

Run (branch → should no-op):
```bash
cd /home/alpibru/workspace/alpibrusl/lex-schema
printf 'refs/heads/main abc refs/heads/main 0000\n' | bash .githooks/pre-push; echo "exit=$?"
```
Expected: no output, `exit=0`.

- [ ] **Step 4: Commit**

```bash
cd /home/alpibru/workspace/alpibrusl/lex-schema
git add .githooks/pre-push
git commit -m "build: pre-push hook publishes to lex-hub on v* tag push"
```

---

### Task 3: Convert `publish.yml` to a CI-only `ci.yml`

**Files:**
- Delete: `/home/alpibru/workspace/alpibrusl/lex-schema/.github/workflows/publish.yml`
- Create: `/home/alpibru/workspace/alpibrusl/lex-schema/.github/workflows/ci.yml`

- [ ] **Step 1: Create `ci.yml` (check/fmt/test, no publish, no token)**

Keeps the existing toolchain-install logic; drops the publish step and the
`LEX_PUBLISH_TOKEN` env. Triggers on pushes, PRs, and tags for public
verification.

Create `.github/workflows/ci.yml` with:

```yaml
name: ci

# Public verification only. Publishing to lex-hub is done locally
# (make publish / pre-push hook) and no longer runs here.

on:
  push:
    branches: ["**"]
    tags: ["v*"]
  pull_request:
  workflow_dispatch:
    inputs:
      tag:
        description: "lex-lang release tag to install (e.g. v0.9.7)"
        required: false
        default: "v0.9.7"

env:
  # Pinned lex toolchain version. Update here when lex-lang ships a new
  # release that lex-schema depends on.
  LEX_VERSION: "v0.9.8"

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - name: Install lex toolchain
        shell: bash
        run: |
          set -euo pipefail
          TAG="${{ github.event.inputs.tag || env.LEX_VERSION }}"
          URL="https://github.com/alpibrusl/lex-lang/releases/download/${TAG}/lex-${TAG}-x86_64-unknown-linux-gnu.tar.gz"
          echo "Downloading lex ${TAG} from ${URL}"
          curl -fsSL "${URL}" -o /tmp/lex.tar.gz
          tar -xzf /tmp/lex.tar.gz -C /tmp
          sudo mv "/tmp/lex-${TAG}-x86_64-unknown-linux-gnu/lex" /usr/local/bin/lex
          sudo chmod +x /usr/local/bin/lex
          lex --version

      - name: Format check
        run: lex fmt --check src/

      - name: Type-check package
        run: lex check --strict src/

      - name: Test
        run: lex test
```

- [ ] **Step 2: Remove the old workflow**

Run: `cd /home/alpibru/workspace/alpibrusl/lex-schema && git rm .github/workflows/publish.yml`
Expected: `rm '.github/workflows/publish.yml'`.

- [ ] **Step 3: Verify the new workflow is valid YAML and references no token**

Run:
```bash
cd /home/alpibru/workspace/alpibrusl/lex-schema
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml')); print('YAML OK')"
grep -c LEX_PUBLISH_TOKEN .github/workflows/ci.yml || echo "no token refs (good)"
```
Expected: `YAML OK`, then `no token refs (good)` (grep finds 0 and the `||` branch prints).

- [ ] **Step 4: Commit**

```bash
cd /home/alpibru/workspace/alpibrusl/lex-schema
git add .github/workflows/ci.yml
git commit -m "ci: convert publish workflow to CI-only (publishing moved local)"
```

---

### Task 4: Delete the now-unused `LEX_PUBLISH_TOKEN` repo secret

**Files:** none (GitHub API action).

- [ ] **Step 1: Confirm the secret exists, then delete it**

Run:
```bash
GIT_CONFIG_NOSYSTEM=1 gh secret list -R alpibrusl/lex-schema
GIT_CONFIG_NOSYSTEM=1 gh secret delete LEX_PUBLISH_TOKEN -R alpibrusl/lex-schema
```
Expected: the list shows `LEX_PUBLISH_TOKEN`; the delete returns no error.

- [ ] **Step 2: Verify it's gone**

Run: `GIT_CONFIG_NOSYSTEM=1 gh secret list -R alpibrusl/lex-schema`
Expected: `LEX_PUBLISH_TOKEN` no longer listed (empty, or only other secrets).

> Note: requires sandbox network access (`dangerouslyDisableSandbox`) as with the
> other `gh`/`ssh` calls in this session.

---

### Task 5: Open the PR

**Files:** none.

- [ ] **Step 1: Push the branch and open a PR**

```bash
cd /home/alpibru/workspace/alpibrusl/lex-schema
GIT_CONFIG_NOSYSTEM=1 git push -u origin chore/local-publish
GIT_CONFIG_NOSYSTEM=1 gh pr create --base main --head chore/local-publish \
  --title "Publish to lex-hub locally; GitHub becomes CI-only mirror" \
  --body "Implements docs/superpowers/specs/2026-06-07-github-independent-publish-design.md. Adds 'make publish' + a pre-push v* tag hook, converts publish.yml to CI-only ci.yml, and removes the LEX_PUBLISH_TOKEN secret. lex-hub publishing no longer depends on GitHub."
```
Expected: PR URL printed.

- [ ] **Step 2: Watch CI and merge**

```bash
GIT_CONFIG_NOSYSTEM=1 gh pr checks --watch
GIT_CONFIG_NOSYSTEM=1 gh pr merge --merge
```
Expected: `check` job passes; PR merges.

---

## Acceptance (manual, after merge)

These require the `lex` CLI installed locally and `LEX_PUBLISH_TOKEN` set —
run them on a dev machine that has the toolchain:

- [ ] `make hooks` installs both `pre-commit` and `pre-push` into `.git/hooks/`.
- [ ] With `LEX_PUBLISH_TOKEN` set, `make publish` runs `lex ci` then publishes and prints a `head_op`.
- [ ] `git tag v0.9.x && git push origin v0.9.x` publishes to lex-hub via the hook; pushing a branch does not.
- [ ] GitHub `ci` workflow runs check/fmt/test and contains no publish step or token.
- [ ] `gh secret list -R alpibrusl/lex-schema` no longer shows `LEX_PUBLISH_TOKEN`.
