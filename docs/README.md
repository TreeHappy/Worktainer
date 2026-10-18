# Configuration

This repository is managed with [Nix](https://nixos.org/): a flake for the
tools, [home-manager](https://github.com/nix-community/home-manager) for the
configuration, and the same sources to build the devbox image.

The environment is declared in `flake.nix` at the repo root. The config sources
it deploys live together in one folder, `nix/configs/files/`. The same sources
feed the host profile and the devbox image.

Three files do three jobs:

- [`nix/lib/tools.nix`](../nix/lib/tools.nix) — the 27 CLI tools this setup
  needs (carapace, starship, atuin, zellij, neovim, node, jj, …), as pinned
  nixpkgs attributes.
- [`nix/lib/deploy.nix`](../nix/lib/deploy.nix) — where each config file goes
  in `$HOME`. One table, used by the host and by the image.
- [`nix/configs/default.nix`](../nix/configs/default.nix) — the content of each
  of those files, read from `nix/configs/files/`.

A machine's own entry point is one small file named after it,
`nix/hosts/<hostname>.nix`, which sets the username and nothing else. Everything
else is shared.

## Layout

```
nix/configs/files/        every config source
  bashrc                  source for ~/.bashrc (aliases, truecolour, fzf colours, tool init)
  atuin/config.toml       source for ~/.config/atuin/config.toml
  bat/                    bat config + vendored Catppuccin Frappé theme
  eza/theme.yml           source for ~/.config/eza/theme.yml (Catppuccin Frappé)
  hunk/config.toml        source for ~/.config/hunk/config.toml (Catppuccin Frappé)
  jjui/                   jjui config + Catppuccin Frappé theme
  lazygit/config.yml      source for ~/.config/lazygit/config.yml (Catppuccin Frappé)
  leaf/                   leaf config + Catppuccin Frappé theme
  opencode/opencode.json  source for ~/.config/opencode/opencode.json (MCP servers)
  opencode/cli.json       source for ~/.config/opencode/cli.json (TUI settings)
  pi/                     pi settings + vendored Catppuccin Frappé theme
  procs/config.toml       source for ~/.config/procs/config.toml (Catppuccin Frappé)
  starship.toml           source for ~/.config/starship.toml (palette, jj prompt)
  workmux/config.yaml     source for ~/.config/workmux/config.yaml (dashboard)
  yazi/                   Yazi file manager config (theme = Catppuccin Frappé)
  yazi/flavors/           vendored Catppuccin Frappé flavor
  zellij/config.kdl       source for ~/.config/zellij/config.kdl
  sshd/sshd_config        sshd config for the devbox image
                         (image-only; nix/lib/deploy.nix keeps it out of the host)
flake.nix                 the tools, the images, and one homeConfiguration per host
nix/lib/                  tools.nix (what to install), deploy.nix (where it goes),
                          image.nix (how the images are built)
nix/modules/host.nix      the home-manager module
nix/hosts/                one file per machine, named after it
sandbox/                  a multi-container sandbox: devbox + ingress/egress + telemetry + openbao
sandbox/openbao/          the sandbox's secrets server (OpenBao in dev mode)
sandbox/ca/               the sandbox's CA (generated per machine, never committed)
docs/                     this documentation
```

## Version control

The repo is a [Jujutsu (jj)](https://jj-vcs.dev/) repository, colocated with git
(`.jj` + `.git`). Drive changes with `jj` (`jj status`, `jj commit -m "..."`),
and push to the GitHub remote (`origin`) with jj's bookmarks — see
[Jujutsu and GitHub](./jj.md).

## Managed files

The table in [`nix/lib/deploy.nix`](../nix/lib/deploy.nix) is the whole of it:

| Target                            | Source                          |
| --------------------------------- | ------------------------------- |
| `~/.bashrc`                       | `bashrc`                        |
| `~/.config/atuin/config.toml`     | `atuin/config.toml`             |
| `~/.config/bat/config`            | `bat/config`                    |
| `~/.config/bat/themes/Catppuccin Frappe.tmTheme` | `bat/themes/…`    |
| `~/.config/eza/theme.yml`         | `eza/theme.yml`                 |
| `~/.config/hunk/config.toml`      | `hunk/config.toml`              |
| `~/.config/jjui/…`                | `jjui/…`                        |
| `~/.config/lazygit/config.yml`    | `lazygit/config.yml`            |
| `~/.config/leaf/…`                | `leaf/…`                        |
| `~/.config/opencode/cli.json`     | `opencode/cli.json`             |
| `~/.config/opencode/opencode.json` | `opencode/opencode.json`       |
| `~/.config/procs/config.toml`     | `procs/config.toml`             |
| `~/.config/starship.toml`         | `starship.toml`                 |
| `~/.config/workmux/config.yaml`   | `workmux/config.yaml`           |
| `~/.config/yazi/…`                | `yazi/…`                        |
| `~/.config/zellij/config.kdl`     | `zellij/config.kdl`             |
| `~/.pi/agent/…`                   | `pi/…`                          |

Files are **copied**, not symlinked: a symlink into `/nix/store` is read-only,
and editing `~/.config/zellij/config.kdl` has to work. The cost is that an
edit made in `$HOME` is not an edit to the source — that is the same trade
`git` makes about a tracked file, and the same one mise's `dotfiles` avoided
only by symlinking into the checkout.

The tools this repo themes are set to Catppuccin Frappé — `bat`, `eza`, `fzf`,
`hunk`, `jjui`, `lazygit`, `leaf`, `opencode`, `pi`, `procs`, `starship`,
`workmux`, `yazi`, and `zellij`. See
[Tools § Themed interfaces](./tools.md#themed-interfaces) for the per-tool
mechanism and the tools left unthemed.

## Quick start

```sh
cd /workspace              # flake.nix lives at the repo root
cp nix/hosts/example.nix nix/hosts/"$(hostname -s)".nix
$EDITOR nix/hosts/"$(hostname -s)".nix      # set `user`
home-manager switch --flake .#"$(hostname -s)"
```

## Documentation

- [Usage](./usage.md) — add, edit, and remove config; daily workflow.
- [Jujutsu and GitHub](./jj.md) — jj concepts, `gh` auth/repo setup, and pushing.
- [Tools](./tools.md) — every CLI tool and how it is wired up.
- [New machine](./new-machine.md) — set up a fresh machine and troubleshooting.
- [Sandbox](./sandbox.md) — the devbox behind controllers: the only way in, the only way out, and three telemetry backends.
- [`nix/README.md`](../nix/README.md) — the provisioning layer: the tool mapping, the images, and why the devbox is built the way it is.
- [Worktainer and OpenSandbox](./comparison-opensandbox.md) — how this sandbox compares to the OpenSandbox platform, and what is worth taking from it.