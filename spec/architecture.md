# Architecture: nx-agents-config

## Purpose

A single bash binary — centralized configuration hub for every coding agent on a
machine. Manages one private git repository (`store/`) that holds configs and session
data for all agents, syncs automatically, and wires symlinks so every agent finds its
files exactly where it expects them.

Key design rules:

- Single bash binary. No npm, no Ruby, no containers at runtime.
- File-based manipulation only. Git is the sync mechanism.
- Everything driven by `nx-agents.toml` (embedded) + `store/config.toml` (user overrides).
- Sync is automatic — no interactive prompts. Designed to run post-session or by cron.
- Commands are idempotent. Running `setup` or `update` twice is safe.

How you manage your git remote (one repo, GitHub vs self-hosted, etc.) is your choice.

---

## Agent Storage Map

### Claude

| Directory | Contains | Store/ status |
| --- | --- | --- |
| `~/.claude/` | projects, sessions, plans, file-history, settings, skills | IN store/ via symlink |
| `~/.claude.json` | global config (preferences, auth ref) | IN store/ via symlink |

`~/.claude/` IS `store/claude/` — the symlink means all Claude data is git-tracked
automatically. No separate backup directory needed.

### OpenCode

OpenCode creates 4 separate directories at startup:

| Directory | Contains | Store/ status |
| --- | --- | --- |
| `~/.config/opencode/` | `opencode.json` — model routing, provider config | IN store/ via symlink |
| `~/.local/share/opencode/` | `opencode.db` — all sessions and messages (SQLite) | IN store/ via symlink → `store/opencode/userdata/` |
| `~/.cache/opencode/` | binary downloads, bundled assets | Excluded — regenerated on demand |
| `~/.local/state/opencode/` | transient runtime state | Excluded — transient |

Inside `~/.local/share/opencode/` (i.e. `store/opencode/userdata/`):

| File / Dir | Tracked in git | Reason |
| --- | --- | --- |
| `opencode.db` | Yes | All session and message history |
| `opencode.db-shm` | No (gitignored) | SQLite shared memory — transient |
| `opencode.db-wal` | No (gitignored) | SQLite write-ahead log — transient |
| `log/` | No (gitignored) | Log files — noise |
| `repos/` | No (gitignored) | Repos cloned by OpenCode — can be very large |

`store/opencode/userdata/.gitignore` contains: `*.db-shm`, `*.db-wal`, `log/`, `repos/`

---

## Filesystem Layout

```
~/.nx-agents-config/                       ← NX_AGENTS_HOME
├── nx-agents-config                       ← self-contained binary
└── store/                                 ← STORE_DIR (private git repo)
    ├── .git/
    ├── config.toml                        ← user overrides (optional)
    ├── claude/
    │   ├── CLAUDE.md
    │   ├── .claude.json
    │   ├── settings.json
    │   ├── skills/      ──────────────── → store/shared/skills/
    │   ├── projects/
    │   └── sessions/
    ├── opencode/
    │   ├── opencode.json
    │   ├── userdata/                      ← symlink target for ~/.local/share/opencode/
    │   │   ├── opencode.db               ← git-tracked
    │   │   └── .gitignore
    │   └── skills/      ──────────────── → store/shared/skills/
    └── shared/                            ← cross-agent, all tools
        ├── skills/
        ├── rules/
        ├── memory/
        └── projects/

External symlinks wired by setup:
  ~/.claude                → store/claude/
  ~/.claude.json           → store/claude/.claude.json
  ~/.config/opencode/      → store/opencode/
  ~/.local/share/opencode/ → store/opencode/userdata/
  ~/.local/bin/nx-agents-config            ← CLI entry point
```

---

## Shared Layer (Cross-Agent)

All resources in `store/shared/` are symlinked into every agent's tool dir.
Any agent can read and write them.

| Resource | Path | Purpose |
| --- | --- | --- |
| Skills | `shared/skills/` | Agent skill definitions (`<name>/SKILL.md`) |
| Rules | `shared/rules/` | Reusable instruction files |
| Memory | `shared/memory/` | Cross-session persistent context |
| Projects | `shared/projects/` | Cross-agent project context dirs |

Each tool wires these via `[[tool.internal]]` symlinks in the TOML.

---

## Binary Build

`build.sh` concatenates all `src/` files, strips `source` lines, embeds
`nx-agents.toml` as base64. The result is a single self-contained bash script.

```
nx-agents.toml    → base64 → DEFAULT_TOML_B64 (embedded in binary header)
src/lib/*.sh      → concatenated (colors, toml, backup, symlink, util)
src/commands/*.sh → concatenated
src/main.sh       → dispatcher appended last
```

After any change to `nx-agents.toml` or `src/`, run `bash build.sh`.
The committed `nx-agents-config` binary must always match the source tree.

---

## TOML Config Schema

Two-layer merge: `nx-agents.toml` (defaults, embedded at build time) merged with
`store/config.toml` (user overrides). Additive by tool name — user entries override
matching defaults, new keys are added.

### `[config]`

```toml
[config]
name    = "nx-agents-config"
home    = "~/.nx-agents-config"
store   = "store"
version = "1.0.0"
```

### `[shared.<key>]`

```toml
[shared.skills]
path = "shared/skills"
desc = "Agent skill definitions (<name>/SKILL.md)"

[shared.rules]
path = "shared/rules"
desc = "Reusable instruction/rule files"

[shared.memory]
path = "shared/memory"
desc = "Cross-session persistent context"

[shared.projects]
path = "shared/projects"
desc = "Cross-agent project context dirs"
```

### `[[tool]]`

```toml
[[tool]]
name         = "opencode"
desc         = "OpenCode AI coding assistant"
external     = "~/.config/opencode"   # main config dir → store/opencode/
data         = "~/.local/share/opencode"
              # used by: backup <tool>      → cp -a data → ~/.tool.bak.TIMESTAMP/
              #          restoreFromBkp     → copy backup back to data
dependencies = ["opencode", "bun"]
```

### `[[tool.external_dir]]`

For tools that store data in multiple system directories. Each entry creates an
additional symlink: `{path}` → `store/{name}/{store_path}/` and writes a
`.gitignore` for files that should not be tracked.

```toml
[[tool.external_dir]]
path       = "~/.local/share/opencode"   # system path to symlink
store_path = "userdata"                  # subdir under store/opencode/
desc       = "OpenCode sessions database"
gitignore  = ["*.db-shm", "*.db-wal", "log/", "repos/"]
```

### `[[tool.internal]]`

Symlinks inside `store/{name}/`. Creates `store/{name}/{from}` → `store/{to}`.

```toml
[[tool.internal]]
from = "skills"
to   = "../shared/skills"
desc = "Shared skills"

[[tool.internal]]
from = "shared-projects"
to   = "../shared/projects"
desc = "Shared project context"
```

### `[[tool.file]]`

Existence checks during setup. Missing = skip with a "create manually" hint.

```toml
[[tool.file]]
path = "opencode.json"
desc = "Global config with model routing"
```

### `[[tool.external_file]]`

Tracks a single file outside the config dir. On first setup: copies the real file
into `store/{name}/`, removes the original, creates a symlink back.

```toml
[[tool.external_file]]
path = "~/.claude.json"
desc = "Claude global config"
# Result: ~/.claude.json → store/claude/.claude.json
```

---

## Sync Behaviour

`sync` runs automatically — no prompts, no questions. Designed to be called after
any agent session or by a cron job.

```
1. git fetch origin
2. if behind remote → git pull --ff-only
                       on conflict: abort with message, require manual pull
3. git add -A
4. if working tree changed → git commit -m "sync: YYYY-MM-DD.HHMMSS"
                              custom message: nx-agents-config sync "my note"
5. if remote configured → git push
```

---

## Command Reference

| Command | What it touches | What it does |
| --- | --- | --- |
| `setup` | store/ + symlinks | First-time scaffold for all tools in TOML |
| `restore <remote>` | store/ + symlinks | Clone remote store + wire all symlinks |
| `sync [msg]` | store/ git | Auto commit + pull + push |
| `update` | store/ + symlinks | Reconcile filesystem to TOML; orphans → `.removed.*` |
| `backup <tool>` | tool data dir | Snapshot to `~/.{tool}.bak.{TIMESTAMP}` |
| `restoreFromBkp [tool]` | tool data dir | Restore from latest snapshot |
| `project add <name>` | `store/shared/projects/` | Create cross-agent project dir |
| `project list` | `store/shared/projects/` | List projects |
| `tool add <name>` | `store/config.toml` | Scaffold a new tool entry |
| `update-tool` | binary | Self-update from GitHub |
| `uninstall` | everything | Backup store + remove all symlinks and dirs |
| `--dry-run` | — | Preview any command without side effects |
