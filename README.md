# Worktainer

A containerized, [Nix](https://nixos.org/)-managed work environment: a dev
container built entirely from a lockfile, plus the configuration that turns it —
or any fresh machine — into a consistent shell.

It doubles as a **sandbox for AI agents**: the same devbox, but with its
network behind two controllers that decide what it can reach and three
telemetry backends that watch the boundary. See
**[Sandbox](./docs/sandbox.md)**.

Everything — the CLI tools, the config files, and the images themselves — is
declared in `flake.nix` at the repo root, and the config sources they deploy
live together in `nix/configs/files/`:

- [`nix/lib/tools.nix`](./nix/lib/tools.nix) — the 27 CLI tools (carapace,
  starship, atuin, zellij, neovim, node, jj, lazygit, workmux, yazi, …) as
  pinned nixpkgs attributes, no `sudo`.
- [`nix/lib/deploy.nix`](./nix/lib/deploy.nix) — where each config file goes in
  `$HOME`. One table, used by the host and by the image.
- `nix/images/` — the three images this repo owns, as nix derivations.
- `nix/hosts/<hostname>.nix` — one small file per machine: the username, and
  nothing else.

So a new machine reproduces the whole environment with:

```sh
cd /workspace            # flake.nix lives at the repo root
cp nix/hosts/example.nix nix/hosts/"$(hostname -s)".nix
$EDITOR nix/hosts/"$(hostname -s)".nix          # set `user`
home-manager switch --flake .#"$(hostname -s)"
```

The sources in `nix/configs/files/` are shared by the devbox image, a fresh
machine, and a VM host later — which is the property that made `dotfiles/` worth
having in the first place, now expressed as a nix table instead of a TOML one.

## Container quick start

```sh
nix build .#sandbox-devbox      # a podman-loadable tarball
podman load < result
podman run -it localhost/sandbox-devbox:latest
```

The image is a nix closure: every package comes from `flake.lock`, the config
comes from `nix/configs/files/`, and it runs as an unprivileged `dev` user
(uid 1000, no `sudo`) in bash with zellij auto-started. It ships nothing else —
no `docs/`, no `.git`, no other sandbox services — because there is no build
context to filter; the store only ever holds what the derivation names.

It still carries no sshd keys: who may log in is decided by the sandbox's
OpenBao, not by the image. See
[`sandbox/dev/README.md`](./sandbox/dev/README.md).

## Layout

```
flake.nix                    the tools, the images, and one homeConfiguration per host
nix/configs/files/           every config source
  bashrc                     -> ~/.bashrc (aliases, fzf colours, starship/… init)
  atuin/config.toml          -> ~/.config/atuin/config.toml
  bat/                       -> ~/.config/bat (config + vendored Catppuccin Frappé theme)
  eza/theme.yml              -> ~/.config/eza/theme.yml (Catppuccin Frappé)
  hunk/config.toml           -> ~/.config/hunk/config.toml (Catppuccin Frappé)
  jjui/                      -> ~/.config/jjui (config + Catppuccin Frappé theme)
  lazygit/config.yml         -> ~/.config/lazygit/config.yml (Catppuccin Frappé)
  leaf/                      -> ~/.config/leaf (config + Catppuccin Frappé theme)
  opencode/opencode.json     -> ~/.config/opencode/opencode.json (MCP servers)
  opencode/cli.json          -> ~/.config/opencode/cli.json (TUI settings)
  pi/                        -> ~/.pi/agent (settings + vendored Catppuccin Frappé theme)
  procs/config.toml          -> ~/.config/procs/config.toml (Catppuccin Frappé)
  starship.toml              -> ~/.config/starship.toml (Catppuccin Frappé palette)
  workmux/config.yaml        -> ~/.config/workmux/config.yaml (Catppuccin Frappé dashboard)
  yazi/                      -> ~/.config/yazi (vendored Catppuccin Frappé flavor)
  zellij/config.kdl          -> ~/.config/zellij/config.kdl
  sshd/sshd_config           the devbox's sshd (image only, never a host)
nix/lib/                     tools.nix, deploy.nix, image.nix
nix/modules/host.nix         the home-manager module
nix/hosts/                   one file per machine
nix/images/                  ingress, egress, devbox — as nix derivations
sandbox/                     the multi-container sandbox (devbox + controllers + telemetry)
sandbox/quadlet/             its systemd units, and the env files they share
sandbox/dev/devbox-init.sh   container start: trust the CA, then sshd
docs/                        documentation
```

## Documentation

- [Usage](./docs/usage.md) — edit config, add a tool, upgrade; daily workflow.
- [Jujutsu and GitHub](./docs/jj.md) — jj concepts, `gh` auth/repo setup, and pushing.
- [Tools](./docs/tools.md) — every CLI tool and how it is wired up.
- [New machine](./docs/new-machine.md) — fresh-machine setup and troubleshooting.
- [Sandbox](./docs/sandbox.md) — the devbox behind controllers; telemetry backends.
- [Worktainer and OpenSandbox](./docs/comparison-opensandbox.md) — this sandbox compared with the OpenSandbox platform.
- [Docs index](./docs/README.md) — overview, layout, and conventions.
- [Nix layer](./nix/README.md) — the tool mapping, the images, and why the devbox is built the way it is.

## Version control

This is a [Jujutsu (jj)](https://jj-vcs.dev/) repository, colocated with git.
Drive changes with jj (`jj status`, `jj commit`, `jj git push -b main`); see
[Jujutsu and GitHub](./docs/jj.md) for the push workflow.

## License

[MIT](./LICENSE) © 2026 TreeHappy
