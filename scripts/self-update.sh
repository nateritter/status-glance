#!/bin/sh
#
# self-update.sh — keep the locally-built StatusGlance.app in sync with origin/main.
#
# Safe to run unattended (launchd) or by hand (`make update`). It is a strict
# no-op unless ALL of these hold:
#   * the checkout is on `main`
#   * the working tree is clean (never disturbs in-progress work)
#   * origin/main has commits the local HEAD doesn't
#   * the update is a clean fast-forward
#
# When it does update, it rebuilds the .app bundle, quits the running instance,
# and relaunches so the menu bar reflects the new build.
set -eu

# Repo root is derived from this script's location — no hardcoded paths.
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

# launchd starts with a bare PATH; make sure git/swift/make/open resolve.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:${PATH:-}"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"; }

# Guard rails — bail quietly on anything that isn't a clean, on-main checkout.
[ "$(git symbolic-ref --short HEAD 2>/dev/null)" = "main" ] || { log "skip: not on main"; exit 0; }
[ -z "$(git status --porcelain)" ] || { log "skip: working tree dirty"; exit 0; }

git fetch --quiet origin main || { log "skip: fetch failed (offline?)"; exit 0; }
LOCAL="$(git rev-parse @)"
REMOTE="$(git rev-parse origin/main)"
[ "$LOCAL" != "$REMOTE" ] || { log "up to date ($LOCAL)"; exit 0; }

# Only act when genuinely BEHIND (local is an ancestor of origin). Local commits
# that aren't pushed yet would otherwise trigger a needless rebuild every cycle.
git merge-base --is-ancestor "$LOCAL" "$REMOTE" || { log "skip: local ahead or diverged"; exit 0; }

log "updating $LOCAL -> $REMOTE"
git merge --ff-only --quiet origin/main || { log "skip: not a fast-forward"; exit 0; }

make app || { log "build failed at $REMOTE — source updated, prior app still running"; exit 1; }
pkill -f 'StatusGlance.app/Contents/MacOS/StatusGlance' 2>/dev/null || true
sleep 1
open "$REPO/StatusGlance.app"
log "updated and relaunched ($REMOTE)"
