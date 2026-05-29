# nx-agents-config — Developer & Agent Guide

Centralized configuration hub for coding agents. Tracks, symlinks, backs up, and git-syncs configs for Claude Code, OpenCode, and custom tools across devices.

## Repository Structure

```
nx-agents-config/
├── bin/nx-agents-config     Dev entrypoint (sources src/ directly, NX_AGENTS_HOME=repo root)
├── src/
│   ├── main.sh              CLI dispatcher, global state, config loading
│   ├── lib/
│   │   ├── colors.sh        Portable ANSI color output
│   │   ├── toml.sh          TOML → JSON (python3 tomllib + jq), config merge
│   │   ├── backup.sh        backup() / backup_store() / move_to_removed()
│   │   ├── symlink.sh       ensure_dir/symlink/external_symlink/external_file_symlink
│   │   └── util.sh          realpath_safe(), run(), check_deps()
│   └── commands/            One file per command (tree, setup, update, sync, project, tool,
│                            backup, restoreFromBkp, update-tool, uninstall)
├── build.sh                 Concatenates all source files → self-contained binary
├── nx-agents-config         Pre-built binary (committed; regenerate with bash build.sh)
├── nx-agents.toml           Default config (embedded in binary as base64 at build time)
├── install.sh               One-curl installer
└── test/                    Container test suite (Docker)
```

## Key Commands

| Command | What it does |
|---|---|
| `tree` | Print configured directory layout |
| `setup` | First-time scaffold: store/, symlinks, git init, external file copies |
| `update` | Reconcile filesystem to config; orphans → `.removed.*` |
| `sync` | Git fetch/pull/push on store/ |
| `backup <tool>` | Copy tool's `data` dir → `~/.{tool}.bak.{TIMESTAMP}` |
| `restoreFromBkp [tool]` | Restore from latest `~/.{tool}.bak.*/` into store/ |
| `project add/list` | Manage per-project context dirs in store/shared/projects/ |
| `tool add` | Interactive scaffold for a new tool entry in store/config.toml |
| `update-tool` | Self-update binary from GitHub |
| `uninstall` | Backup store/ then remove everything |
| `--dry-run` | Preview any command without side effects |

## TOML Config Schema

Two-layer merge: `nx-agents.toml` (defaults, embedded in binary) + `store/config.toml` (user overrides, by tool name).

```toml
[config]
name, repo, home, store, license, version

[shared.<key>]       # shared resources (skills, rules, memory)
path = "shared/..."
desc = "..."

[[tool]]
name = "claude"
desc = "..."
external = "~/.claude"          # external config dir → symlinked from store/{name}/
data = "~/.local/share/tool"    # optional: backup source for `backup` command
dependencies = ["claude"]

[[tool.internal]]    # symlinks within store/{name}/
from = "skills"
to = "../shared/skills"

[[tool.file]]        # files expected inside store/{name}/
path = "CLAUDE.md"

[[tool.external_file]]   # files outside config dir to track
path = "~/.claude.json"
```

## Build & Dev Workflow

```bash
# Dev mode (no build needed — sources src/ directly):
bin/nx-agents-config tree

# Build self-contained binary:
bash build.sh
./nx-agents-config tree

# Run container tests (safe, never touches dev machine):
bash test/run-tests.sh
```

## Design Constraints — Do Not Break

1. **No external deps beyond bash + python3 (≥3.11) + jq + git.** Do not add npm, Ruby, etc.
2. **Binary must be self-contained.** `build.sh` concatenates all source; the resulting file must run with no source tree present.
3. **Default TOML is embedded.** `nx-agents.toml` is base64-encoded into the binary by `build.sh`. Changing the TOML schema requires a rebuild.
4. **Config merging is additive.** User `store/config.toml` overrides defaults by tool name — never silently drops tools.
5. **Always backup before replacing.** Any destructive operation (symlink swap, file move) must call `backup()` first.
6. **`--dry-run` must be respected globally.** All write operations go through `run()` which checks `$DRY_RUN`.
7. **store/ is a separate git repo.** The tool repo (this repo) stays public; store/ is user-controlled with a private remote.
8. **Commands are idempotent.** Running `setup` or `update` twice must be safe — no double-backups, no duplicate symlinks.

## Container Testing

All integration tests run inside Docker — no dev machine files are modified.

```bash
bash test/run-tests.sh          # build image + run all tests
bash test/run-tests.sh --keep   # keep container after failure for debugging
```

Tests validate each command end-to-end against a synthetic `$HOME` with fake tool data.
