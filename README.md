# nx-agents-config

Centralized configuration hub for coding agents (OpenCode, Claude Code, and more).

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
├── setup.sh              Onboarding and management script
├── LICENSE               MIT
└── README.md
```

## Prerequisites

- **`yq`** — for TOML parsing ([install](https://github.com/mikefarah/yq))
  ```bash
  brew install yq        # macOS
  sudo snap install yq   # Linux
  ```

## Quick Start

```bash
# Clone to ~/nx-agents-config
git clone <your-repo-url> ~/nx-agents-config
cd ~/nx-agents-config

# Preview what setup will do
./setup.sh tree

# Run setup (backs up existing configs first)
./setup.sh setup

# Symlink the CLI into PATH for daily use
ln -s "$PWD/setup.sh" ~/.local/bin/nx-agents-config
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

  [[tool.internal]]
  from = "skills"
  to = "../shared/skills"
  desc = "Shared skills"
```

Then run `nx-agents-config update`.

## Daily Sync

Add to `~/.zshrc` or `~/.bashrc`:

```bash
# Sync nx-agents-config on shell start
if command -v nx-agents-config &>/dev/null; then
  nx-agents-config sync 2>/dev/null
fi
```

Or schedule via cron/launchd:

```bash
# ~/Library/LaunchAgents/com.nx-agents-config.sync.plist
# Runs at 9 AM daily
```

## Model Routing

The `opencode.json` defaults to a local Ollama model. Mid-session, use `/model anthropic/claude-sonnet-4-5` to switch to paid — context is preserved.

Override per-project in `opencode.json` at your project root.

## License

MIT
