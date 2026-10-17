# Dotfiles

This repository is managed with [mise](https://mise.jdx.dev/) using the
[`mise dotfiles`](https://mise.jdx.dev/dotfiles.html) feature (alias `mise dot`).

`mise.toml` does two jobs:

- `[tools]` — installs the CLI tools this setup needs (carapace, starship,
  atuin, zellij, neovim, node, jj, …).
- `[dotfiles]` — deploys the config files in this repo into `$HOME` as symlinks.

Both are driven by the same `mise.toml`, so a new machine can reproduce the
whole environment with `mise install && mise dot apply`.

## Layout

```
mise.toml               tools + [dotfiles] entries
bashrc                  source for ~/.bashrc (aliases, truecolour, fzf colours, mise/starship/… init)
atuin/config.toml       source for ~/.config/atuin/config.toml
bat/                    bat config + vendored Catppuccin Frappé theme
eza/theme.yml           source for ~/.config/eza/theme.yml (Catppuccin Frappé)
hunk/config.toml        source for ~/.config/hunk/config.toml (Catppuccin Frappé)
jjui/                   jjui config + Catppuccin Frappé theme
leaf/                   leaf config + Catppuccin Frappé theme
opencode/opencode.json  source for ~/.config/opencode/opencode.json (MCP servers)
opencode/cli.json       source for ~/.config/opencode/cli.json (TUI settings)
pi/                     pi settings + vendored Catppuccin Frappé theme
procs/config.toml       source for ~/.config/procs/config.toml (Catppuccin Frappé)
starship.toml           source for ~/.config/starship.toml (Catppuccin Frappé palette, jj prompt)
yazi/                   Yazi file manager config (theme = Catppuccin Frappé)
yazi/flavors/           vendored Catppuccin Frappé flavor
zellij/config.kdl       source for ~/.config/zellij/config.kdl
docs/                   this documentation
```

## Version control

The repo is a [Jujutsu (jj)](https://jj-vcs.dev/) repository, colocated with git
(`.jj` + `.git`). Drive changes with `jj` (`jj status`, `jj commit -m "..."`),
and push to the GitHub remote (`origin`) with jj's bookmarks — see
[Jujutsu and GitHub](./jj.md).
Only mise's optional dotfile *history* feature (`mise dot save/history/rollback`)
shells out to the git binary — colocation already provides the `.git` store it
expects.

## Managed dotfiles

| Target                            | Source              | Mode                |
| --------------------------------- | ------------------- | ------------------- |
| `~/.bashrc`                       | `bashrc`            | `symlink` (default) |
| `~/.config/atuin/config.toml`     | `atuin/config.toml` | `symlink` (default) |
| `~/.config/bat`                   | `bat`               | `symlink-each`      |
| `~/.config/eza/theme.yml`         | `eza/theme.yml`     | `symlink` (default) |
| `~/.config/hunk/config.toml`      | `hunk/config.toml`  | `symlink` (default) |
| `~/.config/jjui`                  | `jjui`              | `symlink-each`      |
| `~/.config/leaf`                  | `leaf`              | `symlink-each`      |
| `~/.config/opencode/cli.json`     | `opencode/cli.json` | `symlink` (default) |
| `~/.config/opencode/opencode.json` | `opencode/opencode.json` | `symlink` (default) |
| `~/.config/procs/config.toml`     | `procs/config.toml` | `symlink` (default) |
| `~/.config/starship.toml`         | `starship.toml`     | `symlink` (default) |
| `~/.config/yazi`                  | `yazi`              | `symlink-each`      |
| `~/.config/zellij/config.kdl`     | `zellij/config.kdl` | `symlink` (default) |
| `~/.pi/agent`                     | `pi`                | `symlink-each`      |

The tools this repo themes are set to Catppuccin Frappé — `bat`, `eza`, `fzf`,
`hunk`, `jjui`, `leaf`, `opencode`, `pi`, `procs`, `starship`, `yazi`, and
`zellij`. See [Tools § Themed interfaces](./tools.md#themed-interfaces) for the
per-tool mechanism and the tools left unthemed (including `lazygit` and
`workmux`).

The `bat`, `jjui`, `leaf`, `pi`, and `yazi` entries use a **directory source with
`mode = "symlink-each"`**: one entry covers the whole tree, and the target (e.g.
`~/.config/yazi`, `~/.pi/agent`) stays a real directory whose files are
individual symlinks — so tools that write there (`ya pkg`, pi's `auth.json`,
ad-hoc flavors/themes) do not add files to this repo. Use
`exclude = ["*.md", …]` on such an entry to skip files while walking the source.

## Quick start

```sh
cd /workspace        # or wherever you cloned this repo
mise install         # install the CLI tools
mise dot apply       # create the symlinks in $HOME
mise dot status      # confirm everything is applied
```

## Documentation

- [Usage](./usage.md) — add, edit, and remove dotfiles; daily workflow.
- [Jujutsu and GitHub](./jj.md) — jj concepts, `gh` auth/repo setup, and pushing.
- [Tools](./tools.md) — every CLI tool in `[tools]` and how it is wired up.
- [New machine](./new-machine.md) — set up a fresh machine and troubleshooting.
