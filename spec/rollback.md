# Rollback: nx-agents-config

How to recover from any operation going wrong — per command, per layer, and for
catastrophic failures.

---

## What the Tool Backs Up Automatically

Every destructive operation calls `backup()` or `backup_store()` before making
changes. These happen without asking.

| Operation | What gets backed up | Where |
| --- | --- | --- |
| `setup` — existing external dir at symlink path | The original real dir | `~/.{tool}.bak.TIMESTAMP/` |
| `uninstall` | Entire `store/` | `~/.nx-agents-config.store.bak.TIMESTAMP/` |
| `update` — orphan found in store/ | The orphan dir | `NX_AGENTS_HOME/.removed.TIMESTAMP/` |

These backups are **never auto-deleted**. Clean them up manually when you no longer
need them.

---

## Finding Your Backups

```bash
# All tool backups
ls -d ~/.*.bak.* 2>/dev/null

# Specific tool
ls -d ~/.claude.bak.* 2>/dev/null
ls -d ~/.opencode.bak.* 2>/dev/null

# Store/ backup from uninstall
ls -d ~/.nx-agents-config.store.bak.* 2>/dev/null

# Orphan dirs from update
ls -d ~/.nx-agents-config/.removed.* 2>/dev/null
```

Timestamps are in `YYYY-MM-DD.HHMMSS` format. The most recent is always the one
you want unless you are looking for a specific point in time.

---

## Per-Command Rollback

### `setup`

Setup backs up any real directory that exists at the `external` path before replacing
it with a symlink (e.g. a real `~/.claude/` is backed up before becoming a symlink).

Rollback if setup went wrong:

```bash
# 1. Find the backup
ls -d ~/.claude.bak.*

# 2. Remove the bad symlink
rm ~/.claude

# 3. Restore the original dir
cp -a ~/.claude.bak.TIMESTAMP/. ~/.claude/

# 4. Remove the store entry for this tool (optional — data is now back in place)
rm -rf ~/.nx-agents-config/store/claude
```

### `update`

Orphaned dirs are moved, not deleted. They are in `.removed.TIMESTAMP/`.

Rollback if `update` moved something it shouldn't have:

```bash
# Find what was moved
ls ~/.nx-agents-config/.removed.*/

# Move it back
mv ~/.nx-agents-config/.removed.TIMESTAMP/my-tool ~/.nx-agents-config/store/my-tool
```

### `sync`

`sync` makes commits to `store/.git`. Any accidental commit is recoverable via git.

```bash
cd ~/.nx-agents-config/store

# See recent commits
git log --oneline -10

# Undo last sync commit (keeps changes staged)
git reset HEAD~1

# Or hard reset to a specific point
git reset --hard <commit-sha>

# If you reset and need to re-sync properly
nx-agents-config sync
```

If you pushed bad data to the remote:

```bash
cd ~/.nx-agents-config/store
git revert HEAD           # creates a revert commit, safe for shared remotes
git push
```

### `backup <tool>`

`backup` is non-destructive — it only copies. Nothing is removed. If a backup
produced bad output, just delete the backup dir:

```bash
rm -rf ~/.claude.bak.TIMESTAMP/
```

### `restoreFromBkp <tool>`

`restoreFromBkp` is additive — it skips files that already exist in the destination.
It cannot overwrite. If the restore brought in unwanted files:

```bash
# For claude (files go into store/claude/)
cd ~/.nx-agents-config/store
git diff HEAD           # see what changed
git checkout -- .       # revert all unstaged changes

# For opencode (files go to ~/.local/share/opencode/)
# Restore from a known-good backup
cp -a ~/.opencode.bak.GOOD-TIMESTAMP/. ~/.local/share/opencode/
```

### `restore <remote>`

`restore` re-clones store/ after confirming. If the clone produced bad results:

```bash
# The old store/ was removed. Recover from the uninstall-style backup if you had one,
# or re-clone from the remote at a known-good commit:

cd ~/.nx-agents-config/store
git log --oneline -10           # identify a good commit
git reset --hard <good-sha>
nx-agents-config update         # re-wire symlinks to match the reverted store/
```

### `uninstall`

`uninstall` backs up store/ to `~/.nx-agents-config.store.bak.TIMESTAMP/` before
removing everything. Reinstall and recover:

```bash
# 1. Reinstall the binary
curl -fsSL https://raw.githubusercontent.com/nex-ovia/nx-agents-config/main/install.sh | bash

# 2. Move store backup back into place
mkdir -p ~/.nx-agents-config
cp -a ~/.nx-agents-config.store.bak.TIMESTAMP/ ~/.nx-agents-config/store/

# 3. Re-wire all symlinks
nx-agents-config setup
```

---

## Git-Based Rollback (store/ History)

Every `sync` creates a timestamped commit. Store/ is a full git repo — any previous
state is recoverable.

```bash
cd ~/.nx-agents-config/store

# View full history
git log --oneline

# See what a specific commit changed
git show <sha>

# Recover a specific file from an earlier commit
git checkout <sha> -- opencode/opencode.json

# Recover entire store/ to an earlier state
git reset --hard <sha>

# After reset, re-run update to fix any symlinks that diverged
nx-agents-config update
```

---

## OpenCode Database Rollback

`opencode.db` is a SQLite file tracked in git. Rolling it back means checking out
an older version from git history.

```bash
cd ~/.nx-agents-config/store

# Find the last sync that included the DB
git log --oneline -- opencode/userdata/opencode.db

# Check out an older version of the DB
git checkout <sha> -- opencode/userdata/opencode.db

# The DB is now at the older state. Checkpoint to make sure WAL is clean:
sqlite3 opencode/userdata/opencode.db "PRAGMA wal_checkpoint(TRUNCATE);"
```

If the DB file is corrupt (e.g. from a crash mid-write):

```bash
# Try SQLite's integrity check first
sqlite3 ~/.local/share/opencode/opencode.db "PRAGMA integrity_check;"

# If corrupt, restore from the most recent backup
ls -d ~/.opencode.bak.*
cp ~/.opencode.bak.TIMESTAMP/opencode.db ~/.local/share/opencode/opencode.db

# Or restore from git
cd ~/.nx-agents-config/store
git checkout HEAD -- opencode/userdata/opencode.db
```

---

## Full Machine Recovery (Worst Case)

Everything is gone — new machine or catastrophic failure.

```bash
# 1. Install the binary
curl -fsSL https://raw.githubusercontent.com/nex-ovia/nx-agents-config/main/install.sh | bash

# 2. Clone your store from its remote (one command)
nx-agents-config restore git@github.com:you/your-store

# This clones store/, runs setup, wires all symlinks.
# ~/.claude, ~/.config/opencode, ~/.local/share/opencode are all re-linked.
```

If the git remote itself is gone (lost or deleted):

```bash
# Use the most recent uninstall backup if it exists
cp -a ~/.nx-agents-config.store.bak.TIMESTAMP/ ~/.nx-agents-config/store/
nx-agents-config setup

# Or use a manual tool backup
# ~/.claude.bak.TIMESTAMP/ → restore to store/claude/
# ~/.opencode.bak.TIMESTAMP/ → restore to ~/.local/share/opencode/
```

---

## Safety Properties

- `--dry-run` on any command shows what would happen without doing it.
- No destructive operation deletes data without a backup copy.
- `sync` never force-pushes. Conflicts abort cleanly.
- `restoreFromBkp` is always additive — existing files are never overwritten.
- `update` moves orphans to `.removed.*`, never deletes them.
