# nx-agents-config

Centralized configuration hub for coding agents (OpenCode, Claude Code, and more).

## One-curl Install

```bash
curl -fsSL https://raw.githubusercontent.com/nex-ovia/nx-agents-config/main/install.sh | bash
```

To also run setup immediately:

```bash
curl -fsSL https://raw.githubusercontent.com/nex-ovia/nx-agents-config/main/install.sh | bash -s -- --setup
```

## Prerequisites

- **python3** (≥ 3.11, for TOML parsing)
- **jq** ([install](https://jqlang.github.io/jq/download/))
- **git** (for store/ sync)

```bash
brew install jq        # macOS
sudo apt install jq    # Debian/Ubuntu
```

## Structure

```
~/.nx-agents-config/
├── nx-agents-config      Self-contained binary
├── store/                Your data (separate git repo)
│   ├── config.toml       User overrides
│   ├── opencode/         OpenCode config (→ ~/.config/opencode/)
│   ├── claude/           Claude config (→ ~/.claude/, ~/.claude.json)
│   │   ├── .claude.json        Claude global config (tracked)
│   │   ├── projects/           Per-project sessions
│   │   ├── sessions/           Session data
│   │   ├── plans/              Architecture plans
│   │   ├── file-history/       Undo/redo history
│   │   └── ...                 Other Claude runtime data
│   └── shared/
│       ├── projects/           Cross-agent project copies
│       ├── skills/             Agent skill definitions (shared via symlink)
│       ├── rules/              Reusable instruction/rule files
│       └── memory/             Cross-session persistent context store
└── shared/ → store/shared/
```

## Commands

| Command | Description |
|---|---|---|
| `nx-agents-config tree` | Show full directory tree from config |
| `nx-agents-config setup` | Initial setup: create store/, shared/, symlinks |
| `nx-agents-config update` | Reconcile filesystem to match config (orphans → `.removed/`) |
| `nx-agents-config sync` | Git sync your store/ data |
| `nx-agents-config restoreFromBkp` | Restore Claude data from `~/.claude.bak.*/` into store/ |
| `nx-agents-config project add <name>` | Create a new project in store/ |
| `nx-agents-config project list` | List projects |
| `nx-agents-config tool add <name>` | Scaffold a new tool in store/config.toml |
| `nx-agents-config update-tool` | Self-update the binary from GitHub |
| `nx-agents-config uninstall` | Backup store/ + remove everything |
| `nx-agents-config --dry-run` | Preview any command without making changes |

## Adding a New Tool

```bash
nx-agents-config tool add my-agent
# Follow prompts for description and config path
nx-agents-config update   # create external symlinks
```

Or add to your store's `config.toml`:

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

## Development

```bash
git clone https://github.com/nex-ovia/nx-agents-config.git
cd nx-agents-config

# Use dev entry point (sources src/ directly)
bin/nx-agents-config tree

# Build self-contained binary
bash build.sh
./nx-agents-config tree
```

## License

MIT
