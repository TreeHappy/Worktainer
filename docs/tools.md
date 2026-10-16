# Tools

Everything in `[tools]` is installed by [mise](https://mise.jdx.dev/) with
`mise install` — prebuilt binaries into `~/.local/share/mise`, no distro
packages and no `sudo`. The only things not managed here are `git` (mise cannot
provide it) and, in the Docker image, `libatomic1` (needed by Node, see the
`Dockerfile`).

```sh
mise install     # install/refresh everything in [tools]
mise upgrade     # move the "latest" pins to newer releases
```

Versions are pinned to `latest`, so there is no lock file: `mise upgrade`
(or a fresh `mise install`) picks up new releases.

## Installed tools

The list mirrors `[tools]` in `mise.toml`, alphabetically.

| Tool | What it is | Wired up in this repo |
| ---- | ---------- | --------------------- |
| `atuin` | Shell history database with fuzzy search, stats, and optional sync | `atuin init bash` (Ctrl-R); config in `atuin/config.toml` |
| `bat` | `cat` with syntax highlighting and git markers | Aliased as `cat` (`--paging=never`) |
| `carapace` | Completion engine that generates tab-completions for many CLIs | `carapace _carapace bash` |
| `duf` | Disk usage/free viewer (modern `df`) | — |
| `dust` | Disk usage visualizer, shows the biggest directories first (modern `du`) | — |
| `eza` | `ls` replacement with colors, icons, and git status | Backs the `ls`, `ll`, `la`, `lt` aliases |
| `fd` | Fast, user-friendly `find` | — |
| `fzf` | Fuzzy finder for pipes, history, and file lists | Left standalone — no shell hook, so it does not fight atuin over Ctrl-R |
| `gh` | GitHub CLI (PRs, issues, releases, `gh api`) | — |
| `leaf` | Terminal Markdown viewer/TUI reader; also `--diff` and `--picker` | — |
| `hunk` | Terminal diff/log pager for reviewing changesets | — |
| `jj` | [Jujutsu](https://jj-vcs.dev/) VCS; this repo is a jj + git colocated repo | Repo workflow (`jj status`, `jj commit`) |
| `jjui` | Interactive TUI for Jujutsu | — |
| `jq` | JSON processor | — |
| `neovim` | Modal editor | `$EDITOR`/`$VISUAL`; also yazi's `edit` opener |
| `node` | JavaScript runtime | Backs the npm-based tools below |
| `opencode` | Terminal AI coding agent (`npm:@opencode/cli`, built on install) | Global config in `opencode/opencode.json` (MCP servers below), TUI settings in `opencode/cli.json` (theme `catppuccin-frappe`) |
| `pi` | AI coding assistant with read/bash/edit/write tools | — |
| `procs` | Modern `ps` replacement (process viewer) | — |
| `ripgrep` | Fast recursive search (`rg`) | — |
| `starship` | Cross-shell prompt | `starship init bash` |
| `yazi` | Terminal file manager | Config in `yazi/`; Catppuccin Frappé flavor |
| `yq` | YAML/JSON/XML processor | — |
| `zellij` | Terminal multiplexer with layouts and sessions | Auto-starts (last line of `bashrc`); config in `zellij/config.kdl` |
| `zoxide` | Smarter `cd` that learns your directories (`z`, `zi`) | `zoxide init bash` |

### Backends

Most names resolve through the mise registry. Two need an explicit backend
because the bare name is ambiguous or unregistered:

```toml
"github:RivoLink/leaf" = "latest"
"aqua:dalance/procs"  = "latest"
```

`opencode` is an npm package, so it declares the build it needs:

```toml
opencode = { version = "latest", allow_builds = ["@opencode/cli"] }
```

## Shell integration

`bashrc` is what turns installed tools into a usable shell:

```bash
alias ls='eza'; alias ll='eza -l --git'; alias la='eza -la'; alias lt='eza --tree'
alias cat='bat --paging=never'

export EDITOR=nvim
export VISUAL=nvim

eval "$(mise activate bash)"      # tools on PATH, per-directory versions
eval "$(mise completion bash)"    # tab-completion for mise itself
eval "$(starship init bash)"      # prompt
eval "$(carapace _carapace bash)" # completions for other CLIs
eval "$(atuin init bash)"         # Ctrl-R history search
eval "$(zoxide init bash)"        # z / zi
```

The `mise activate` line is written with an explicit path
(`/root/.local/bin/mise`) because it runs before mise is on `PATH`.

## MCP servers

Two tools in `[tools]` ship a built-in MCP (Model Context Protocol) server over
stdio, so AI coding agents can call them as tools:

| Server | Command | What it offers |
| ------ | ------- | -------------- |
| `atuin` | `atuin mcp` | `atuin_history` (search shell history with exit codes, cwd, duration), `atuin_output`, `atuin_output_search` |
| `carapace` | `carapace --mcp` | `complete` (context-aware shell completions), `list_macros`, `codegen` |

Both are declared in `opencode/opencode.json` and deployed to
`~/.config/opencode/opencode.json` (OpenCode's global config), so every project
— not just this repo — gets them. Verify the connection state with:

```sh
opencode mcp list     # ✓ atuin connected · ✓ carapace connected
```

Notes:

- The commands are bare names, so they resolve through `PATH`: OpenCode must be
  launched from a shell where `mise activate` has run (any interactive shell
  started from this repo's `bashrc`).
- `atuin_history` works against the local SQLite database with no extra setup;
  `atuin_output` / `atuin_output_search` additionally need Atuin's output
  capture (daemon + pty-proxy) running.

### The rest of `[tools]`

None of the other installed tools expose an MCP server (checked: bat, duf,
dust, eza, fd, fzf, gh, hunk, jj, jjui, jq, leaf, neovim, node, pi, procs,
ripgrep, starship, yazi, yq, zellij, zoxide). Two related cases worth knowing:

- **mise itself** has one: `mise mcp` exposes project tools, tasks, env, and
  config as MCP resources/tools over stdio. It is not wired up here — one entry
  in `opencode/opencode.json` adds it if wanted.
- **`pi`** (`pi mcp …`) and **`opencode`** (`opencode mcp add/list`) have `mcp`
  subcommands, but those *manage MCP clients* — they do not serve MCP.

## Themed interfaces

Three TUIs are set to Catppuccin Frappé:

- **Zellij** — built-in `catppuccin-frappe` theme, set in `zellij/config.kdl`.
- **Yazi** — the vendored `catppuccin-frappe` flavor (see below).
- **neovim/others** — not themed here; neovim's own config is out of scope for
  this repo.

## Adding or removing a tool

1. Add/remove the entry in `[tools]` (keep it alphabetical).
2. Run `mise install`.

```toml
[tools]
hyperfine = "latest"          # example: plain registry name
```

To drop a tool: remove its line, then optionally `mise uninstall <tool>`.

## Related documentation

- [Usage](./usage.md) — dotfile workflow (`mise dot add/apply/status`).
- [New machine](./new-machine.md) — fresh-machine setup and troubleshooting.
