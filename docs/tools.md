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
| `bat` | `cat` with syntax highlighting and git markers | Aliased as `cat` (`--paging=never`); Catppuccin Frappé theme in `bat/` |
| `carapace` | Completion engine that generates tab-completions for many CLIs | `carapace _carapace bash` |
| `duf` | Disk usage/free viewer (modern `df`) | — |
| `dust` | Disk usage visualizer, shows the biggest directories first (modern `du`) | — |
| `eza` | `ls` replacement with colors, icons, and git status | Backs the `ls`, `ll`, `la`, `lt` aliases; Catppuccin Frappé theme in `eza/theme.yml` |
| `fd` | Fast, user-friendly `find` | — |
| `fzf` | Fuzzy finder for pipes, history, and file lists | Left standalone — no shell hook, so it does not fight atuin over Ctrl-R; Catppuccin Frappé colours via `FZF_DEFAULT_OPTS` |
| `gh` | GitHub CLI (PRs, issues, releases, `gh api`) | — |
| `leaf` | Terminal Markdown viewer/TUI reader; also `--diff` and `--picker` | Catppuccin Frappé theme (hand-written) in `leaf/` |
| `hunk` | Terminal diff/log pager for reviewing changesets | Built-in `catppuccin-frappe` theme in `hunk/config.toml` |
| `jj` | [Jujutsu](https://jj-vcs.dev/) VCS; this repo is a jj + git colocated repo | Repo workflow (`jj status`, `jj commit`) |
| `jjui` | Interactive TUI for Jujutsu | Catppuccin Frappé theme in `jjui/` |
| `jq` | JSON processor | — |
| `neovim` | Modal editor | `$EDITOR`/`$VISUAL`; also yazi's `edit` opener |
| `node` | JavaScript runtime | Backs the npm-based tools below |
| `opencode` | Terminal AI coding agent (`npm:@opencode/cli`, built on install) | Global config in `opencode/opencode.json` (MCP servers below), TUI settings in `opencode/cli.json` (theme `catppuccin-frappe`) |
| `pi` | AI coding assistant with read/bash/edit/write tools | Catppuccin Frappé theme (vendored) in `pi/` |
| `procs` | Modern `ps` replacement (process viewer) | Catppuccin Frappé 256-colour `[style]` in `procs/config.toml` |
| `ripgrep` | Fast recursive search (`rg`) | — |
| `starship` | Cross-shell prompt | `starship init bash`; Catppuccin Frappé palette in `starship.toml`; prompt shows **jj** state (git modules disabled) |
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

unset LS_COLORS                       # let eza use its own Catppuccin Frappé theme
export COLORTERM=truecolor            # advertise truecolour to pi, jjui, opencode, …
export FZF_DEFAULT_OPTS="--color=…"   # Catppuccin Frappé colours for fzf
export EDITOR=nvim
export VISUAL=nvim

eval "$(mise activate bash)"      # tools on PATH, per-directory versions
eval "$(mise completion bash)"    # tab-completion for mise itself
eval "$(starship init bash)"      # prompt
eval "$(carapace _carapace bash)" # completions for other CLIs
eval "$(atuin init bash)"         # Ctrl-R history search
eval "$(zoxide init bash)"        # z / zi

zellij                            # auto-start the multiplexer
```

The `mise activate`/`completion` lines use an explicit path
(`$HOME/.local/bin/mise`, falling back to `mise` on `PATH`) because they run
before mise is on `PATH` — a per-user install lives in `~/.local/bin`, the same
place the Docker image puts it.

### jj prompt

Starship has no native Jujutsu support, so `starship.toml` replaces the built-in
git modules (`git_branch`, `git_status` are `disabled = true`) with two custom
modules that call `jj`:

- `custom.jj` — the current bookmark (or the short change id when the working
  copy has no bookmark), plus `conflict`/`divergent`/`immutable` flags when
  present.
- `custom.jj_status` — the change summary (`<files>f <added>+ <removed>-`),
  hidden when the change is empty.

Both pass `--ignore-working-copy`: this keeps the prompt fast and stops it from
snapshotting or locking the repo. The state shown is therefore the last
snapshot, which any `jj` command refreshes. Adapted from the
[jj Starship wiki](https://github.com/jj-vcs/jj/wiki/Starship).

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

Every tool that supports theming is set to **Catppuccin Frappé**. Colours come
from the official palette (<https://github.com/catppuccin/catppuccin>), and roles
follow the palette's [style guide](https://github.com/catppuccin/catppuccin/blob/main/docs/style-guide.md)
(backgrounds, text, syntax).

| Tool | Mechanism | Source |
| ---- | --------- | ------ |
| `bat` | vendored `Catppuccin Frappe.tmTheme` + `--theme="Catppuccin Frappe"` | `bat/config`, `bat/themes/` |
| `eza` | native `theme.yml` (its own hex palette) | `eza/theme.yml` |
| `fzf` | `--color=…` colourspec via `FZF_DEFAULT_OPTS` | `bashrc` |
| `hunk` | built-in `catppuccin-frappe` theme | `hunk/config.toml` |
| `jjui` | hand-written theme following the style guide | `jjui/config.toml`, `jjui/themes/` |
| `leaf` | hand-written theme (leaf's own `theme.toml` format) | `leaf/config.toml`, `leaf/themes/` |
| `opencode` | built-in `catppuccin-frappe` name | `opencode/cli.json` |
| `pi` | vendored `catppuccin-frappe` theme (from the `catppuccin-pi-theme` npm package) | `pi/settings.json`, `pi/themes/` |
| `procs` | `[style]` mapping — 256-colour approximation (procs has no hex support) | `procs/config.toml` |
| `starship` | palette + per-module colour overrides; jj custom modules (git modules disabled) | `starship.toml` |
| `yazi` | vendored `catppuccin-frappe` flavor | `yazi/theme.toml`, `yazi/flavors/` |
| `zellij` | built-in `catppuccin-frappe` theme | `zellij/config.kdl` |

Three notes:

- **bat keeps a compiled theme cache.** After any change to `bat/themes/` (and on
  a fresh machine after `mise dot apply`) run it once, or bat falls back to its
  default theme:

  ```sh
  bat cache --build           # locally: mise exec -- bat cache --build
  ```

  The Docker image runs this at build time.
- **eza ignores its theme while `LS_COLORS` is set**, which the stock Ubuntu
  `~/.bashrc` sets from `dircolors` — hence the `unset LS_COLORS` line (that
  block is inherited from Ubuntu's default bashrc).
- **Many themes need truecolour.** In the container `COLORTERM` is unset and
  `TERM` is only `xterm-256color`, so truecolour-aware tools (`pi`, `jjui`,
  `opencode`, `leaf`) would approximate the Frappé hex palette with 256 colours.
  `bashrc` exports `COLORTERM=truecolor` so they emit it faithfully.

### Not themed

Checked and left alone, usually because a faithful Frappé palette is impossible:

| Tool | Why |
| ---- | --- |
| `atuin` | Custom themes exist, but only accept named ANSI colours — no hex, so no faithful Frappé. |
| `duf` | Only `dark`, `light`, and `ansi` themes. |
| `dust` | Colours are fixed; no theme config. |
| `carapace` | Has a style system, but it controls completion layout rather than a global colour theme. |
| `fd`, `gh`, `jq`, `yq`, `ripgrep`, `zoxide`, `node` | No theming support. |
| `neovim` | Its config is out of scope for this repo. |

`leaf`'s `syntax` setting names a bundled [syntect](https://github.com/trishume/syntect)
theme for fenced code blocks; it cannot load bat's `.tmTheme`, so it uses
`base16-mocha.dark` as the closest dark scheme.

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
