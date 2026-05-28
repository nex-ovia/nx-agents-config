# nx-agents-config

Centralized configuration hub for coding agents (OpenCode, Claude Code, and more).

## One-curl Install

```bash
curl -fsSL https://raw.githubusercontent.com/nex-ovia/nx-agents-config/main/bootstrap.sh | bash
```

To also run setup immediately:

```bash
curl -fsSL https://raw.githubusercontent.com/nex-ovia/nx-agents-config/main/bootstrap.sh | bash -s -- --setup
```

## Prerequisites

- **git**
- **python3** (≥ 3.11, for TOML parsing)
- **jq** ([install](https://jqlang.github.io/jq/download/))

```bash
brew install jq        # macOS
sudo apt install jq    # Debian/Ubuntu
```

## Structure

```
nx-agents-config/
├── shared/               # Cross-tool shared assets
│   ├── skills/           Agent skill definitions (<name>/SKILL.md)
│   ├── rules/            Reusable instruction/rule files
│   └── memory/           Persistent context store
├── opencode/             OpenCode AI → ~/.config/opencode/
├── claude/               Claude Code → ~/.claude/
├── nx-agents.toml        Manifest (single source of truth)
├── setup.sh              CLI tool (tree/setup/update/sync/status)
├── bootstrap.sh          One-curl install script
├── LICENSE               MIT
└── README.md
```

## Commands

| Command | Description |
|---|---|
| `nx-agents-config tree` | Show full directory tree from TOML |
| `nx-agents-config setup` | Initial setup: backup + symlink everything |
| `nx-agents-config update` | Reconcile filesystem to match TOML (orphans → `.removed/`) |
| `nx-agents-config sync` | `git pull --ff-only` |
| `nx-agents-config status` | Tree + git status |
| `nx-agents-config tool add <name>` | Scaffold a new tool entry in TOML |
| `nx-agents-config --dry-run` | Preview any command without changes |

## Adding a New Tool

```bash
nx-agents-config tool add my-agent
# Follow prompts for description and config path
nx-agents-config update   # create external symlinks
```

Or edit `nx-agents.toml` directly:

```toml
[[tool]]
name = "my-agent"
desc = "My custom coding agent"
external = "~/.config/my-agent"
dependencies = ["my-agent-cli", "git"]

[[tool.internal]]
from = "skills"
to = "../shared/skills"
desc = "Shared skills"
```

Then run `nx-agents-config update`.

## Dependencies

Each tool can declare CLI dependencies. `setup` and `update` check if they're on PATH and warn if missing:

```toml
dependencies = ["opencode", "bun"]
```

Shared resources have no dependencies — they are passive data (skills, rules, memory).

## Daily Sync

Add to `~/.zshrc` or `~/.bashrc`:

```bash
if command -v nx-agents-config &>/dev/null; then
  nx-agents-config sync 2>/dev/null
fi
```

Or schedule via cron/launchd.

## Model Routing

The `opencode.json` defaults to a local Ollama model. Mid-session, use `/model anthropic/claude-sonnet-4-5` to switch to paid — context is preserved.

Override per-project in `opencode.json` at your project root.

## License

MIT
