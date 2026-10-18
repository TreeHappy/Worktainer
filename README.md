# Worktainer

A containerized, [mise](https://mise.jdx.dev/)-managed work environment: an
Ubuntu dev-container image plus the dotfiles that turn it — or any fresh
machine — into a consistent shell.

It doubles as a **sandbox for AI agents**: the same devbox, but with its
network behind two controllers that decide what it can reach and three
telemetry backends that watch the boundary. See
**[Sandbox](./docs/sandbox.md)**.

Everything — the CLI tools, the config files, and the few system packages mise
cannot install per-user — is declared in `mise.toml` at the repo root, and the
config sources it deploys live together in `dotfiles/`:

- `[tools]` — installs the CLI tools (carapace, starship, atuin, zellij,
  neovim, node, jj, lazygit, workmux, yazi, …) into `~/.local/share/mise`, as
  prebuilt binaries, no `sudo`.
- `[dotfiles]` — deploys the tracked configs in `dotfiles/` into `$HOME` as symlinks.
- `[bootstrap.packages]` — a handful of apt packages (podman and its rootless
  helpers, for the sandbox).

So a new machine reproduces the whole environment with:

```sh
cd /workspace    # mise.toml lives at the repo root
mise install     # install the CLI tools
mise dot apply   # deploy the dotfiles into $HOME
mise bootstrap   # the apt packages in [bootstrap.packages]
```

The sources in `dotfiles/` are shared by the container image, a fresh machine,
and a VM host later. The image carries its own copy of the manifest at
`sandbox/dev/mise.toml` (same `[tools]` and `[dotfiles]`, no
`[bootstrap.packages]`).

## Container quick start

```sh
docker build -f sandbox/dev/Dockerfile -t worktainer .   # from the repo root
docker run -it worktainer
```

The image builds everything as an unprivileged `dev` user (uid 1000, no `sudo`)
that owns the mise toolchain and the dotfiles checkout: it installs mise, runs
`mise install && mise dot apply` (plus `bat cache --build`), and drops you into
bash with zellij auto-started.

The build context is the repository root, and the image's only `COPY`s take
`dotfiles/` (the real sources, so there are no copies to refresh) and
`sandbox/dev/mise.toml` (the container's config). It still ships nothing else:
no `docs/`, no `.git`, no other sandbox services (`.dockerignore` and the
selective `COPY` keep it that way).

## Layout

```
dotfiles/               every config source (the manifest lives at the repo root)
  bashrc                -> ~/.bashrc (aliases, fzf colours, mise/starship/… init)
  atuin/config.toml     -> ~/.config/atuin/config.toml
  bat/                  -> ~/.config/bat (config + vendored Catppuccin Frappé theme)
  eza/theme.yml         -> ~/.config/eza/theme.yml (Catppuccin Frappé)
  hunk/config.toml      -> ~/.config/hunk/config.toml (Catppuccin Frappé)
  jjui/                 -> ~/.config/jjui (config + Catppuccin Frappé theme)
  lazygit/config.yml    -> ~/.config/lazygit/config.yml (Catppuccin Frappé)
  leaf/                 -> ~/.config/leaf (config + Catppuccin Frappé theme)
  opencode/opencode.json -> ~/.config/opencode/opencode.json (MCP servers)
  opencode/cli.json     -> ~/.config/opencode/cli.json (TUI settings)
  pi/                   -> ~/.pi/agent (settings + vendored Catppuccin Frappé theme)
  procs/config.toml     -> ~/.config/procs/config.toml (Catppuccin Frappé)
  starship.toml         -> ~/.config/starship.toml (Catppuccin Frappé palette)
  workmux/config.yaml   -> ~/.config/workmux/config.yaml (Catppuccin Frappé dashboard)
  yazi/                 -> ~/.config/yazi (vendored Catppuccin Frappé flavor)
  zellij/config.kdl     -> ~/.config/zellij/config.kdl
mise.toml               host config: [tools] + [dotfiles] + [bootstrap.packages]
sandbox/                the multi-container sandbox (devbox + controllers + telemetry)
sandbox/dev/Dockerfile  the devbox image (was the root Dockerfile)
sandbox/dev/mise.toml   container config: [tools] + [dotfiles]
docs/                   documentation
```

## Documentation

- [Usage](./docs/usage.md) — add, edit, and remove dotfiles; daily workflow.
- [Jujutsu and GitHub](./docs/jj.md) — jj concepts, `gh` auth/repo setup, and pushing.
- [Tools](./docs/tools.md) — every CLI tool in `[tools]` and how it is wired up.
- [New machine](./docs/new-machine.md) — fresh-machine setup and troubleshooting.
- [Sandbox](./docs/sandbox.md) — the devbox behind controllers; telemetry backends.
- [Worktainer and OpenSandbox](./docs/comparison-opensandbox.md) — this sandbox compared with the OpenSandbox platform.
- [Docs index](./docs/README.md) — overview, layout, and conventions.

## Version control

This is a [Jujutsu (jj)](https://jj-vcs.dev/) repository, colocated with git.
Drive changes with jj (`jj status`, `jj commit`, `jj git push -b main`); see
[Jujutsu and GitHub](./docs/jj.md) for the push workflow.

## License

[MIT](./LICENSE) © 2026 TreeHappy
