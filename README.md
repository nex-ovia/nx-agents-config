# nx-agents-config

Centralized configuration hub for coding agents. Manages one private git repository
(`store/`) that holds configs and session data for all agents, syncs automatically,
and wires symlinks so every agent finds its files exactly where it expects them.

Works with **OpenCode**, **Claude Code**, and any tool you add via TOML config.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/nex-ovia/nx-agents-config/main/install.sh | bash
```

Run setup immediately after install:

```bash
curl -fsSL https://raw.githubusercontent.com/nex-ovia/nx-agents-config/main/install.sh | bash -s -- --setup
```

## Prerequisites

- **bash** (≥ 4.0)
- **python3** (≥ 3.11, for TOML parsing)
- **jq** ([install](https://jqlang.github.io/jq/download/))
- **git**

```bash
brew install jq        # macOS
sudo apt install jq    # Debian/Ubuntu
```

## How It Works

`setup` wires symlinks from standard agent paths into `store/`:

```
~/.claude                    →  store/claude/
~/.claude.json               →  store/claude/.claude.json
~/.config/opencode/          →  store/opencode/
~/.local/share/opencode/     →  store/opencode/userdata/
```

Every agent finds its files at the paths it expects. `store/` is a private git
repo you sync to any remote — restore on a new machine with one command.

## Directory Layout

```
~/.nx-agents-config/
├── nx-agents-config          Self-contained binary
└── store/                    Your data (separate private git repo)
    ├── config.toml           User overrides (optional)
    ├── claude/               Claude config (→ ~/.claude/)
    │   ├── CLAUDE.md
    │   ├── .claude.json      (→ ~/.claude.json)
    │   ├── projects/
    │   ├── sessions/
    │   ├── plans/
    │   ├── skills/           (→ store/shared/skills/)
    │   └── shared-projects/  (→ store/shared/projects/)
    ├── opencode/             OpenCode config (→ ~/.config/opencode/)
    │   ├── opencode.json
    │   ├── userdata/         OpenCode sessions DB (→ ~/.local/share/opencode/)
    │   │   └── opencode.db   All sessions and messages (git-tracked)
    │   ├── skills/           (→ store/shared/skills/)
    │   └── shared-projects/  (→ store/shared/projects/)
    └── shared/               Cross-agent resources
        ├── skills/           Agent skill definitions (<name>/SKILL.md)
        ├── rules/            Reusable instruction files
        ├── memory/           Cross-session persistent context
        └── projects/         Cross-agent project context dirs
```

## Commands

| Command | What it does |
| --- | --- |
| `setup` | First-time scaffold: store/, symlinks, git init |
| `restore <remote>` | Clone remote store and wire all symlinks (new device) |
| `sync [message]` | Auto commit + pull + push (no prompts) |
| `update` | Reconcile filesystem to config; orphans → `.removed.*` |
| `backup <tool>` | Snapshot tool data to `~/.{tool}.bak.{timestamp}/` |
| `restoreFromBkp [tool]` | Restore from latest `~/.{tool}.bak.*/` |
| `project add <name>` | Create cross-agent project dir in store/shared/projects/ |
| `project list` | List projects |
| `tool add <name>` | Scaffold a new tool entry in store/config.toml |
| `tree` | Show full directory layout from config |
| `update-tool` | Self-update binary from GitHub |
| `uninstall` | Backup store/ then remove everything |
| `--dry-run <cmd>` | Preview any command without making changes |

## First Device

```bash
nx-agents-config setup
# → Initialize git? [Y/n]           Y
# → Remote URL?                      git@github.com:you/store
# → store/ wired, all symlinks created
# → write opencode.json, CLAUDE.md, etc.

nx-agents-config sync
# → committed and pushed to remote
```

## New Device (Restore)

One command clones your store and wires all symlinks:

```bash
curl -fsSL https://raw.githubusercontent.com/nex-ovia/nx-agents-config/main/install.sh | bash
nx-agents-config restore git@github.com:you/store
# → git clone store/
# → ~/.claude, ~/.claude.json, ~/.config/opencode, ~/.local/share/opencode all linked
# → all sessions, projects, skills, memory available immediately
```

## Sync

`sync` runs without prompts — safe to call after any session or from a cron job:

```bash
nx-agents-config sync                   # auto message: "sync: 2026-05-29.143022"
nx-agents-config sync "after refactor"  # custom message
```

Before committing, `sync` checkpoints the OpenCode SQLite WAL so the committed
`opencode.db` is always consistent. On conflict, it aborts with a clear message
instead of prompting.

## Backup and Restore

### Point-in-time snapshot

```bash
nx-agents-config backup claude     # → ~/.claude.bak.2026-05-29.143022/
nx-agents-config backup opencode   # → ~/.opencode.bak.2026-05-29.143022/
```

Backups are never auto-deleted. Restore from the latest snapshot:

```bash
nx-agents-config restoreFromBkp claude
nx-agents-config restoreFromBkp opencode
```

Restore is additive — existing files are skipped, never overwritten.

## Cross-Agent Sharing

Skills, rules, memory, and project context in `store/shared/` are automatically
symlinked into every agent's directory. To share a skill with all agents, drop a
`<name>/SKILL.md` into `store/shared/skills/` — no registration step.

## Adding a Tool

```bash
nx-agents-config tool add my-agent
nx-agents-config update
```

Or add directly to `store/config.toml`:

```toml
[[tool]]
name         = "my-agent"
desc         = "My custom coding agent"
external     = "~/.config/my-agent"
data         = "~/.local/share/my-agent"
dependencies = ["my-agent-cli"]

[[tool.internal]]
from = "skills"
to   = "../shared/skills"
desc = "Shared skills"
```

Run `nx-agents-config update` to wire the new symlinks.

## Development

```bash
git clone https://github.com/nex-ovia/nx-agents-config.git
cd nx-agents-config

# Dev mode — sources src/ directly, no build needed
bin/nx-agents-config tree

# Build self-contained binary
bash build.sh
./nx-agents-config tree

# Run unit + integration tests (Docker, never touches dev machine)
bash test/run-tests.sh

# Run full lifecycle test (requires GGUF model — see test/run-lifecycle.sh)
bash test/run-lifecycle.sh
```

## License

MIT
