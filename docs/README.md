# Dotfiles

This repository is managed with [mise](https://mise.jdx.dev/) using the
[`mise dotfiles`](https://mise.jdx.dev/dotfiles.html) feature (alias `mise dot`).

The environment is declared in `mise.toml` at the repo root, and the config
sources it deploys live together in one folder, `dotfiles/`. The same sources
feed the container image and a fresh machine; the image carries its own copy of
the manifest at `sandbox/dev/mise.toml`.

`mise.toml` does three jobs:

- `[tools]` — installs the CLI tools this setup needs (carapace, starship,
  atuin, zellij, neovim, node, jj, …).
- `[dotfiles]` — deploys the config files in `dotfiles/` into `$HOME` as symlinks.
- `[bootstrap.packages]` — a few apt packages mise cannot install as per-user
  tools (podman and its rootless helpers, for the [sandbox](./sandbox.md)).

`sandbox/dev/mise.toml` is the container's variant of the same config: the same
`[tools]` and the same `[dotfiles]` plus the devbox's own sshd config (nothing
the host would deploy), minus `[bootstrap.packages]` (the image never runs
`mise bootstrap`). Run mise from the repo root; a new machine reproduces the
whole environment with `mise install && mise dot apply` (plus `mise bootstrap`
for the apt packages).

## Layout

```
dotfiles/                every config source (the manifest lives at the repo root)
  bashrc                 source for ~/.bashrc (aliases, truecolour, fzf colours, mise/starship/… init)
  atuin/config.toml      source for ~/.config/atuin/config.toml
  bat/                   bat config + vendored Catppuccin Frappé theme
  eza/theme.yml          source for ~/.config/eza/theme.yml (Catppuccin Frappé)
  hunk/config.toml       source for ~/.config/hunk/config.toml (Catppuccin Frappé)
  jjui/                  jjui config + Catppuccin Frappé theme
  lazygit/config.yml     source for ~/.config/lazygit/config.yml (Catppuccin Frappé)
  leaf/                  leaf config + Catppuccin Frappé theme
  opencode/opencode.json source for ~/.config/opencode/opencode.json (MCP servers)
  opencode/cli.json      source for ~/.config/opencode/cli.json (TUI settings)
  pi/                    pi settings + vendored Catppuccin Frappé theme
  procs/config.toml      source for ~/.config/procs/config.toml (Catppuccin Frappé)
  starship.toml          source for ~/.config/starship.toml (Catppuccin Frappé palette, jj prompt)
  workmux/config.yaml    source for ~/.config/workmux/config.yaml (Catppuccin Frappé dashboard)
  yazi/                  Yazi file manager config (theme = Catppuccin Frappé)
  yazi/flavors/          vendored Catppuccin Frappé flavor
  zellij/config.kdl      source for ~/.config/zellij/config.kdl
  sshd/sshd_config       sshd config for the devbox container
                         (deployed by sandbox/dev/mise.toml only, not on the host)
mise.toml                host config: [tools] + [dotfiles] + [bootstrap.packages]
sandbox/                 a multi-container sandbox: devbox + ingress/egress + telemetry + openbao
sandbox/dev/mise.toml    container config: [tools] + [dotfiles]
sandbox/openbao/         the sandbox's secrets server (OpenBao in dev mode)
docs/                    this documentation
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

Sources are relative to `mise.toml` at the repo root, so each source reads
`dotfiles/<path>`.

| Target                            | Source                          | Mode                |
| --------------------------------- | ------------------------------- | ------------------- |
| `~/.bashrc`                       | `dotfiles/bashrc`               | `symlink` (default) |
| `~/.config/atuin/config.toml`     | `dotfiles/atuin/config.toml`    | `symlink` (default) |
| `~/.config/bat`                   | `dotfiles/bat`                  | `symlink-each`      |
| `~/.config/eza/theme.yml`         | `dotfiles/eza/theme.yml`        | `symlink` (default) |
| `~/.config/hunk/config.toml`      | `dotfiles/hunk/config.toml`     | `symlink` (default) |
| `~/.config/jjui`                  | `dotfiles/jjui`                 | `symlink-each`      |
| `~/.config/lazygit/config.yml`    | `dotfiles/lazygit/config.yml`   | `symlink` (default) |
| `~/.config/leaf`                  | `dotfiles/leaf`                 | `symlink-each`      |
| `~/.config/opencode/cli.json`     | `dotfiles/opencode/cli.json`    | `symlink` (default) |
| `~/.config/opencode/opencode.json` | `dotfiles/opencode/opencode.json` | `symlink` (default) |
| `~/.config/procs/config.toml`     | `dotfiles/procs/config.toml`    | `symlink` (default) |
| `~/.config/starship.toml`         | `dotfiles/starship.toml`        | `symlink` (default) |
| `~/.config/workmux/config.yaml`   | `dotfiles/workmux/config.yaml`  | `symlink` (default) |
| `~/.config/yazi`                  | `dotfiles/yazi`                 | `symlink-each`      |
| `~/.config/zellij/config.kdl`     | `dotfiles/zellij/config.kdl`    | `symlink` (default) |
| `~/.pi/agent`                     | `dotfiles/pi`                   | `symlink-each`      |

The tools this repo themes are set to Catppuccin Frappé — `bat`, `eza`, `fzf`,
`hunk`, `jjui`, `lazygit`, `leaf`, `opencode`, `pi`, `procs`, `starship`,
`workmux`, `yazi`, and `zellij`. See
[Tools § Themed interfaces](./tools.md#themed-interfaces) for the per-tool
mechanism and the tools left unthemed.

The `bat`, `jjui`, `leaf`, `pi`, and `yazi` entries use a **directory source with
`mode = "symlink-each"`**: one entry covers the whole tree, and the target (e.g.
`~/.config/yazi`, `~/.pi/agent`) stays a real directory whose files are
individual symlinks — so tools that write there (`ya pkg`, pi's `auth.json`,
ad-hoc flavors/themes) do not add files to this repo. Use
`exclude = ["*.md", …]` on such an entry to skip files while walking the source.

## Quick start

```sh
cd /workspace         # mise.toml lives at the repo root
mise install          # install the CLI tools
mise dot apply        # create the symlinks in $HOME
mise dot status       # confirm everything is applied
```

## Documentation

- [Usage](./usage.md) — add, edit, and remove dotfiles; daily workflow.
- [Jujutsu and GitHub](./jj.md) — jj concepts, `gh` auth/repo setup, and pushing.
- [Tools](./tools.md) — every CLI tool in `[tools]` and how it is wired up.
- [New machine](./new-machine.md) — set up a fresh machine and troubleshooting.
- [Sandbox](./sandbox.md) — the devbox behind controllers: the only way in, the only way out, and three telemetry backends.
