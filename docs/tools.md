# Tools

Every tool here is a pinned nixpkgs attribute in
[`nix/lib/tools.nix`](../nix/lib/tools.nix), installed by home-manager into
`~/.nix-profile`. No distro packages, no `sudo`, and a lock file: `flake.lock`
records exactly which versions the profile is.

```sh
cd /workspace    # flake.nix lives at the repo root
nix flake update nixpkgs                              # move the pins
home-manager switch --flake .#"$(hostname -s)"       # apply
nix build .#host-tools                                # ask what changed
```

`git` is part of the tool set even though it has no entry above: jj, jjui,
lazygit and workmux all shell out to it. Podman stays on apt — see
[New machine](./new-machine.md#podman-for-the-sandbox-only).

## Installed tools

The list mirrors the `host` set in
[`nix/lib/tools.nix`](../nix/lib/tools.nix), alphabetically. Note the names:
five of these are not the nixpkgs attribute of the same name (`jj` is
`jujutsu`, `yq` is `yq-go`, `leaf` is `leaf-markdown-viewer`, `pi` is
`pi-coding-agent`, `node` is `nodejs_22`) — see
[`nix/README.md`](../nix/README.md).

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
| `jj` | [Jujutsu](https://jj-vcs.dev/) VCS; this repo is a jj + git colocated repo | Repo workflow (`jj status`, `jj commit`); pushing to GitHub in [Jujutsu and GitHub](./jj.md) |
| `jjui` | Interactive TUI for Jujutsu | Catppuccin Frappé theme in `jjui/` |
| `jq` | JSON processor | — |
| `lazygit` | Terminal UI for Git (stage, commit, branches, rebase, stash) | Aliased as `lg`; Catppuccin Frappé theme in `lazygit/config.yml` — see [Git workflow tools](#git-workflow-tools) |
| `neovim` | Modal editor | `$EDITOR`/`$VISUAL`; also yazi's `edit` opener |
| `node` | JavaScript runtime | Backs the npm-based tools below |
| `opencode` | Terminal AI coding agent (`npm:@opencode/cli`, built on install) | Global config in `opencode/opencode.json` (MCP servers below), TUI settings in `opencode/cli.json` (theme `catppuccin-frappe`) |
| `pi` | AI coding assistant with read/bash/edit/write tools | Catppuccin Frappé theme (vendored) in `pi/` |
| `procs` | Modern `ps` replacement (process viewer) | Catppuccin Frappé 256-colour `[style]` in `procs/config.toml` |
| `ripgrep` | Fast recursive search (`rg`) | — |
| `starship` | Cross-shell prompt | `starship init bash`; Catppuccin Frappé palette in `starship.toml`; prompt shows **jj** state (git modules disabled) |
| `workmux` | git worktrees paired with multiplexer windows (and optional AI-agent panes) for parallel work | Aliased as `wm`; auto-detects Zellij; Catppuccin Frappé dashboard in `workmux/config.yaml` — see [Git workflow tools](#git-workflow-tools) |
| `yazi` | Terminal file manager | Config in `yazi/`; Catppuccin Frappé flavor |
| `yq` | YAML/JSON/XML processor | — |
| `zellij` | Terminal multiplexer with layouts and sessions | Auto-starts (last line of `bashrc`); config in `zellij/config.kdl` |
| `zoxide` | Smarter `cd` that learns your directories (`z`, `zi`) | `zoxide init bash` |

### Where each one comes from

All of them are nixpkgs attributes except `workmux`, which is not packaged and
so is a flake input (upstream ships its own flake):

```nix
workmux.url = "github:raine/workmux";
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

eval "$(starship init bash)"      # prompt
eval "$(carapace _carapace bash)" # completions for other CLIs
eval "$(atuin init bash)"         # Ctrl-R history search
eval "$(zoxide init bash)"        # z / zi

zellij                            # auto-start the multiplexer
```

`$HOME/.nix-profile/bin` is prepended near the top of the same file, and that
one line is what replaced `mise activate`: the tools are in the profile
home-manager maintains, and this file also runs on a machine where no switch has
happened yet.

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

## Git workflow tools

Two installed tools drive **Git** directly rather than jj. Both are plain
binaries — no shell init — and both rely on the `git` binary, which the Docker
image installs (and the [jj workflow](./jj.md) needs anyway). `bashrc` adds the
conventional short aliases `lg` (lazygit) and `wm` (workmux).

- **`lazygit`** — a terminal UI for Git: staging, commits, branches, rebase,
  stash, and so on. It is most at home in an ordinary Git repository; in this
  jj-colocated repo it operates on the same `.git` store, so mixing it with jj
  can be surprising. Its Catppuccin Frappé theme lives in `lazygit/config.yml`,
  deployed to `~/.config/lazygit/config.yml`.
- **`workmux`** — runs each [git worktree](https://git-scm.com/docs/git-worktree)
  in its own multiplexer window, optionally with AI-agent panes, so features can
  be developed in parallel without branch switching:

  ```sh
  wm add feature/auth        # create a worktree + window and switch to it
  wm list                    # list worktrees with status
  wm merge                   # merge, then remove worktree/window/branch
  wm dashboard               # TUI overview of active agents
  ```

  workmux needs a multiplexer and detects one from the environment: since the
  tracked `bashrc` auto-starts **Zellij**, `$ZELLIJ` is set and the Zellij
  backend is chosen (`WORKMUX_BACKEND=zellij` forces it). Upstream marks that
  backend **experimental** — it relies on newer Zellij CLI actions and is
  documented as needing a Zellij built from source — so expect rough edges.
  Worktrees need `git` (installed); `--pr` and fork checkouts also need `gh`.
  The global config (`workmux/config.yaml` → `~/.config/workmux/config.yaml`)
  turns off Nerd Font icons and applies a Frappé dashboard palette; per-project
  overrides still go in a `.workmux.yaml` at the project root.

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
  launched from a shell whose `PATH` includes `~/.nix-profile/bin`, which this
  repo's `bashrc` arranges.
- `atuin_history` works against the local SQLite database with no extra setup;
  `atuin_output` / `atuin_output_search` additionally need Atuin's output
  capture (daemon + pty-proxy) running.

### The rest of `[tools]`

None of the other installed tools expose an MCP server (checked: bat, duf,
dust, eza, fd, fzf, gh, hunk, jj, jjui, jq, lazygit, leaf, neovim, node, pi,
procs, ripgrep, starship, workmux, yazi, yq, zellij, zoxide). Two related cases
worth knowing:

- **Nix itself** has no MCP server, but `nix-mcp` does if you want an agent to
  evaluate expressions. Not wired up here — one entry in
  `nix/configs/files/opencode/opencode.json` adds it if wanted.
- **`pi`** (`pi mcp …`) and **`opencode`** (`opencode mcp add/list`) have `mcp`
  subcommands, but those *manage MCP clients* — they do not serve MCP.

## Themed interfaces

Every tool this repo themes is set to **Catppuccin Frappé**. Colours come
from the official palette (<https://github.com/catppuccin/catppuccin>), and roles
follow the palette's [style guide](https://github.com/catppuccin/catppuccin/blob/main/docs/style-guide.md)
(backgrounds, text, syntax).

| Tool | Mechanism | Source |
| ---- | --------- | ------ |
| `bat` | vendored `Catppuccin Frappe.tmTheme` + `--theme="Catppuccin Frappe"` | `nix/configs/files/bat/` |
| `eza` | native `theme.yml` (its own hex palette) | `eza/theme.yml` |
| `fzf` | `--color=…` colourspec via `FZF_DEFAULT_OPTS` | `bashrc` |
| `hunk` | built-in `catppuccin-frappe` theme | `hunk/config.toml` |
| `jjui` | hand-written theme following the style guide | `jjui/config.toml`, `jjui/themes/` |
| `lazygit` | vendor-neutral `gui.theme` colours (Catppuccin's official Frappé/mauve preset) | `lazygit/config.yml` |
| `leaf` | hand-written theme (leaf's own `theme.toml` format) | `leaf/config.toml`, `leaf/themes/` |
| `opencode` | built-in `catppuccin-frappe` name | `opencode/cli.json` |
| `pi` | vendored `catppuccin-frappe` theme (from the `catppuccin-pi-theme` npm package) | `pi/settings.json`, `pi/themes/` |
| `procs` | `[style]` mapping — 256-colour approximation (procs has no hex support) | `procs/config.toml` |
| `starship` | palette + per-module colour overrides; jj custom modules (git modules disabled) | `starship.toml` |
| `workmux` | dashboard `theme.custom` palette override (no built-in Frappé scheme) | `workmux/config.yaml` |
| `yazi` | vendored `catppuccin-frappe` flavor | `yazi/theme.toml`, `yazi/flavors/` |
| `zellij` | built-in `catppuccin-frappe` theme | `zellij/config.kdl` |

Three notes:

- **bat keeps a compiled theme cache.** After any change to
  `nix/configs/files/bat/themes/` run it once, or bat falls back to its default
  theme:

  ```sh
  bat cache --build
  ```

  The devbox image does not need this: the theme is a file in the image rather
  than something the build compiles.
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

1. Add or remove the entry in `host` in
   [`nix/lib/tools.nix`](../nix/lib/tools.nix) — alphabetical, and as an
   attribute rather than a name, because five of them are not called what their
   command is.
2. `home-manager switch --flake .#"$(hostname -s)"`.

```nix
host = {
  hyperfine = pkgs.hyperfine;   # example
  # ...
};
```

To drop a tool: remove its line and switch. The profile drops it.

See [Usage § Add a tool](./usage.md#add-a-tool) for the pitfalls.

## Related documentation

- [Usage](./usage.md) — editing config, adding a tool, upgrading.
- [New machine](./new-machine.md) — fresh-machine setup and troubleshooting.
