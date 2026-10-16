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
bashrc                  source for ~/.bashrc
atuin/config.toml       source for ~/.config/atuin/config.toml
opencode/opencode.json  source for ~/.config/opencode/opencode.json (MCP servers)
opencode/cli.json       source for ~/.config/opencode/cli.json (TUI settings)
yazi/                   Yazi file manager config (theme = Catppuccin Frappé)
yazi/flavors/           vendored Catppuccin Frappé flavor
zellij/config.kdl       source for ~/.config/zellij/config.kdl
docs/                   this documentation
```

## Version control

The repo is a [Jujutsu (jj)](https://jj-vcs.dev/) repository, colocated with git
(`.jj` + `.git`). Drive changes with `jj` (`jj status`, `jj commit -m "..."`).
Only mise's optional dotfile *history* feature (`mise dot save/history/rollback`)
shells out to the git binary — colocation already provides the `.git` store it
expects.

## Managed dotfiles

| Target                            | Source              | Mode                |
| --------------------------------- | ------------------- | ------------------- |
| `~/.bashrc`                       | `bashrc`            | `symlink` (default) |
| `~/.config/atuin/config.toml`     | `atuin/config.toml` | `symlink` (default) |
| `~/.config/opencode/opencode.json` | `opencode/opencode.json` | `symlink` (default) |
| `~/.config/opencode/cli.json` | `opencode/cli.json` | `symlink` (default) |
| `~/.config/yazi`                  | `yazi`              | `symlink-each`      |
| `~/.config/zellij/config.kdl`     | `zellij/config.kdl` | `symlink` (default) |

Both Zellij and Yazi use Catppuccin Frappé: Zellij's built-in
`catppuccin-frappe` theme (`zellij/config.kdl`), and the vendored
`catppuccin-frappe` flavor for Yazi (`yazi/theme.toml` +
`yazi/flavors/catppuccin-frappe.yazi/`).

The Yazi entry uses a **directory source with `mode = "symlink-each"`**: one
entry covers the whole `yazi/` tree, and `~/.config/yazi` stays a real directory
whose files are individual symlinks — so tools that write there (`ya pkg`, ad-hoc
flavors) do not add files to this repo. Use `exclude = ["*.md", …]` on such an
entry to skip files while walking the source.

## Quick start

```sh
cd /workspace        # or wherever you cloned this repo
mise install         # install the CLI tools
mise dot apply       # create the symlinks in $HOME
mise dot status      # confirm everything is applied
```

## Documentation

- [Usage](./usage.md) — add, edit, and remove dotfiles; daily workflow.
- [Tools](./tools.md) — every CLI tool in `[tools]` and how it is wired up.
- [New machine](./new-machine.md) — set up a fresh machine and troubleshooting.
