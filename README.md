# Worktainer

A containerized, [mise](https://mise.jdx.dev/)-managed work environment: an
Ubuntu dev-container image plus the dotfiles that turn it — or any fresh
machine — into a consistent shell.

Everything, both the CLI tools and the config files, is declared in one
`mise.toml`:

- `[tools]` — installs the CLI tools (carapace, starship, atuin, zellij,
  neovim, node, jj, yazi, …) into `~/.local/share/mise`, as prebuilt binaries,
  no `sudo`.
- `[dotfiles]` — deploys the tracked configs into `$HOME` as symlinks.

So a new machine reproduces the whole environment with:

```sh
mise install     # install the CLI tools
mise dot apply   # deploy the dotfiles into $HOME
```

## Container quick start

```sh
docker build -t worktainer .
docker run -it worktainer
```

The image installs mise, runs `mise install && mise dot apply`, and drops you
into bash with zellij auto-started.

## Layout

```
Dockerfile              dev-container image
mise.toml               [tools] + [dotfiles] entries
bashrc                  -> ~/.bashrc
atuin/config.toml       -> ~/.config/atuin/config.toml
yazi/                   -> ~/.config/yazi (vendored Catppuccin Frappé flavor)
zellij/config.kdl       -> ~/.config/zellij/config.kdl
docs/                   documentation
```

## Documentation

- [Usage](./docs/usage.md) — add, edit, and remove dotfiles; daily workflow.
- [Tools](./docs/tools.md) — every CLI tool in `[tools]` and how it is wired up.
- [New machine](./docs/new-machine.md) — fresh-machine setup and troubleshooting.
- [Docs index](./docs/README.md) — overview, layout, and conventions.

## Version control

This is a [Jujutsu (jj)](https://jj-vcs.dev/) repository, colocated with git.
Drive changes with jj (`jj status`, `jj commit`, `jj git push -b main`).

## License

[MIT](./LICENSE) © 2026 TreeHappy
