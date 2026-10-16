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

The image builds everything as an unprivileged `dev` user (uid 1000, no `sudo`)
that owns the mise toolchain and the dotfiles checkout: it installs mise, runs
`mise install && mise dot apply` (plus `bat cache --build`), and drops you into
bash with zellij auto-started.

## Layout

```
Dockerfile              dev-container image (non-root `dev` user)
mise.toml               [tools] + [dotfiles] entries
bashrc                  -> ~/.bashrc (aliases, fzf colours, mise/starship/… init)
atuin/config.toml       -> ~/.config/atuin/config.toml
bat/                    -> ~/.config/bat (config + vendored Catppuccin Frappé theme)
eza/theme.yml           -> ~/.config/eza/theme.yml (Catppuccin Frappé)
hunk/config.toml        -> ~/.config/hunk/config.toml (Catppuccin Frappé)
jjui/                   -> ~/.config/jjui (config + Catppuccin Frappé theme)
leaf/                   -> ~/.config/leaf (config + Catppuccin Frappé theme)
opencode/opencode.json  -> ~/.config/opencode/opencode.json (MCP servers)
opencode/cli.json       -> ~/.config/opencode/cli.json (TUI settings)
pi/                     -> ~/.pi/agent (settings + vendored Catppuccin Frappé theme)
procs/config.toml       -> ~/.config/procs/config.toml (Catppuccin Frappé)
starship.toml           -> ~/.config/starship.toml (Catppuccin Frappé palette)
yazi/                   -> ~/.config/yazi (vendored Catppuccin Frappé flavor)
zellij/config.kdl       -> ~/.config/zellij/config.kdl
docs/                   documentation
```

## Documentation

- [Usage](./docs/usage.md) — add, edit, and remove dotfiles; daily workflow.
- [Jujutsu and GitHub](./docs/jj.md) — jj concepts, `gh` auth/repo setup, and pushing.
- [Tools](./docs/tools.md) — every CLI tool in `[tools]` and how it is wired up.
- [New machine](./docs/new-machine.md) — fresh-machine setup and troubleshooting.
- [Docs index](./docs/README.md) — overview, layout, and conventions.

## Version control

This is a [Jujutsu (jj)](https://jj-vcs.dev/) repository, colocated with git.
Drive changes with jj (`jj status`, `jj commit`, `jj git push -b main`); see
[Jujutsu and GitHub](./docs/jj.md) for the push workflow.

## License

[MIT](./LICENSE) © 2026 TreeHappy
