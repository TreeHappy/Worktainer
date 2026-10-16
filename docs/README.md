# Dotfiles

This repository is managed with [mise](https://mise.jdx.dev/) using the
[`mise dotfiles`](https://mise.jdx.dev/dotfiles.html) feature (alias `mise dot`).

`mise.toml` does two jobs:

- `[tools]` — installs the CLI tools this setup needs (carapace, starship,
  zellij, neovim, node, jj, …).
- `[dotfiles]` — deploys the config files in this repo into `$HOME` as symlinks.

Both are driven by the same `mise.toml`, so a new machine can reproduce the
whole environment with `mise install && mise dot apply`.

## Layout

```
mise.toml           tools + [dotfiles] entries
bashrc              source for ~/.bashrc
zellij/config.kdl   source for ~/.config/zellij/config.kdl
docs/               this documentation
```

## Version control

The repo is a [Jujutsu (jj)](https://jj-vcs.dev/) repository, colocated with git
(`.jj` + `.git`). Drive changes with `jj` (`jj status`, `jj commit -m "..."`).
Only mise's optional dotfile *history* feature (`mise dot save/history/rollback`)
shells out to the git binary — colocation already provides the `.git` store it
expects.

## Managed dotfiles

| Target                           | Source             | Mode              |
| -------------------------------- | ------------------ | ----------------- |
| `~/.bashrc`                      | `bashrc`           | `symlink` (default) |
| `~/.config/zellij/config.kdl`    | `zellij/config.kdl`| `symlink` (default) |

## Quick start

```sh
cd /workspace        # or wherever you cloned this repo
mise install         # install the CLI tools
mise dot apply       # create the symlinks in $HOME
mise dot status      # confirm everything is applied
```

## Documentation

- [Usage](./usage.md) — add, edit, and remove dotfiles; daily workflow.
- [New machine](./new-machine.md) — set up a fresh machine and troubleshooting.
