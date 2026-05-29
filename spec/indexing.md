# Indexing: How Agents Load Their Files

Whether flat files and the OpenCode SQLite database need indexing for agents to
discover and load them correctly when everything is wired via symlinks.

---

## Claude

### How Claude finds its files

Claude is told: `~/.claude` is its home directory. Every file and dir inside it
is Claude's own. The `~/.claude → store/claude/` symlink is completely transparent
— Claude never knows it is in a symlinked directory.

| Claude looks here | What it finds | Wired by |
| --- | --- | --- |
| `~/.claude/projects/` | Project context dirs | store/claude/projects/ |
| `~/.claude/sessions/` | Session history files | store/claude/sessions/ |
| `~/.claude/plans/` | Architecture plans | store/claude/plans/ |
| `~/.claude/file-history/` | Undo/redo history | store/claude/file-history/ |
| `~/.claude/CLAUDE.md` | Global instructions | store/claude/CLAUDE.md |
| `~/.claude/settings.json` | Preferences | store/claude/settings.json |
| `~/.claude/skills/` | Skill definitions | store/claude/skills/ → store/shared/skills/ |

**No external indexing needed.** Claude scans its own directories at load time.
The symlink means the git-tracked store/ IS Claude's working directory.

### `~/.claude.json`

A single JSON file (`~/.claude.json → store/claude/.claude.json`). Claude reads
it directly by path. No indexing needed.

---

## OpenCode

### Config file

`~/.config/opencode/opencode.json` is the only config file. OpenCode reads it by
path at startup. The symlink `~/.config/opencode/ → store/opencode/` is transparent.

### Session database (`opencode.db`)

OpenCode stores everything in a single SQLite3 database:

```
~/.local/share/opencode/opencode.db
```

After wiring: `~/.local/share/opencode/ → store/opencode/userdata/`

OpenCode finds its database at the expected path — the symlink is transparent.
SQLite manages its own internal indexing (B-tree indexes per table). No external
index is needed.

**WAL mode and sync**

SQLite runs in WAL (Write-Ahead Log) mode by default. During active use, writes
go to `opencode.db-wal` first. The main `opencode.db` file may not reflect the
latest changes until the WAL is checkpointed.

This matters for git sync: if `opencode.db-wal` exists and is non-empty when
`git add -A` runs, the committed `opencode.db` will be missing those writes.

**Fix**: `sync` must checkpoint the WAL before `git add`:

```bash
DB="$STORE_DIR/opencode/userdata/opencode.db"
if [[ -f "$DB" ]]; then
  sqlite3 "$DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
fi
```

`TRUNCATE` mode: checkpoints all WAL frames into the main DB and resets the WAL
to zero bytes. This ensures `opencode.db` is the single source of truth before
git tracks it. The WAL file is gitignored — only the DB is committed.

**When OpenCode is running during sync**: SQLite's WAL allows concurrent readers
and writers. `wal_checkpoint(TRUNCATE)` will wait for any in-progress write
transaction to complete before checkpointing. In practice, a checkpoint during
an active OpenCode session may be a no-op or partial — the sync commit will still
capture whatever was checkpointed. The next sync will pick up the rest.

Do not sync while OpenCode is actively writing a long response — wait for it to
finish the session.

---

## Shared Resources

These live in `store/shared/` and are symlinked into each tool dir via
`[[tool.internal]]`. Agents discover them by scanning their local symlink path.

### Skills

```
store/shared/skills/
  <skill-name>/
    SKILL.md         ← agent reads this
    (other files)
```

Each agent scans its local `skills/` directory (which is a symlink to `shared/skills/`).
No index needed — agents read all `*/SKILL.md` files found in the directory.

Adding a skill: drop a `<name>/SKILL.md` into `store/shared/skills/`. It is
immediately visible to all agents via their symlinks. No registration step.

### Rules

```
store/shared/rules/
  *.md              ← agent reads all .md files
```

No index needed. Agents load all `.md` files found in their `rules/` symlink.

### Memory

```
store/shared/memory/
  <agent-specific files>
```

Each agent manages its own memory format. The shared directory means any agent
can read another agent's memory files if the format is known. No central index —
agents are responsible for their own memory file discovery.

### Projects

```
store/shared/projects/
  <project-name>/
    meta.toml        ← project metadata (name, desc, created, agents)
    context.md       ← project instructions and context
    sessions.toml    ← session references
```

Each project is a directory. Agents discover projects by scanning `shared-projects/`
(their internal symlink to `store/shared/projects/`).

**Project manifest (`projects/index.toml`)**

For fast discovery without scanning every subdirectory — relevant when many projects
exist — a manifest file is useful:

```toml
# store/shared/projects/index.toml
# Auto-updated by `nx-agents-config project add` and `project remove`

[[project]]
name    = "my-api"
desc    = "API rewrite"
created = "2026-05-28"
agents  = ["claude", "opencode"]

[[project]]
name    = "data-pipeline"
desc    = "ETL refactor"
created = "2026-05-20"
agents  = ["opencode"]
```

`project add` writes to this file. `project list` reads from it (falls back to
directory scan if the file is absent for backwards compatibility).

Agents can load `index.toml` to get the project list without traversing the
directory — this is especially useful for agents with tool-use that enumerate
available projects.

---

## Summary: What Needs What

| Resource | Indexing needed | Who manages it | Notes |
| --- | --- | --- | --- |
| Claude files | None | Claude itself | Symlink is transparent |
| `~/.claude.json` | None | Claude itself | Single file, read by path |
| OpenCode config | None | OpenCode itself | Single JSON file |
| `opencode.db` | SQLite internal | SQLite | WAL checkpoint required before sync |
| Skills | None | Agent scans dir | Drop file = immediately available |
| Rules | None | Agent scans dir | All `.md` files loaded |
| Memory | Agent-specific | Each agent | No central index |
| Projects | Optional manifest | `nx-agents-config` | `index.toml` for fast enumeration |

---

## Symlink Transparency

All symlinks used by this tool are standard filesystem symlinks. Agents do not
need to be symlink-aware:

- `~/.claude → store/claude/` — Claude reads/writes as if `~/.claude/` is a real dir
- `~/.config/opencode → store/opencode/` — OpenCode reads config by path
- `~/.local/share/opencode → store/opencode/userdata/` — OpenCode opens DB by path
- `store/claude/skills → store/shared/skills/` — Claude scans skills at `~/.claude/skills/`

The only exception is SQLite's WAL mode (see above) — WAL files are created alongside
the DB file, inside the symlinked directory, which is correct behaviour.
