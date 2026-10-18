# New machine

Set up a fresh machine from this repo.

## Prerequisites

### Nix

The tools and the configuration come from Nix, so that is the one dependency
that has to exist before anything else.

```sh
# see https://nixos.org/download — the single-user install is fine
sh <(curl -L https://nixos.org/nix/install) --daemon
```

If your distribution already packages it (`apt install nix-bin`, `pacman -S
nix`, …), skip that. Either way, you want the `nix` binary on `PATH` — the
tracked `bashrc` adds `~/.nix-profile/bin` if it is not already there, and
`nix profile install nixpkgs#git` or your distribution's package gets it there.

Multi-user (`--daemon`) is needed if you want `home-manager` to install into a
shared profile; the single-user install works for a personal machine.

### Podman, for the sandbox only

Podman and its rootless helpers need capabilities a per-user binary cannot set
up, so they come from apt rather than from the toolchain:

```sh
sudo apt install podman uidmap passt
```

They are for the [sandbox](./sandbox.md) only. Without them the configuration
works fine — it is a developer's environment, not a container runtime. Nix is
*not* used for podman: rootless podman from nixpkgs drags in subuid handling and
cgroup setup that is genuinely painful outside NixOS, and nothing here is
blocked by keeping it on apt.

## Install the configuration

```sh
# Clone with jj (or `git clone`, which works on this colocated repo)
jj git clone <repo-url> ~/src/dandbox
cd ~/src/dotfiles           # flake.nix lives at the repo root

cp nix/hosts/example.nix nix/hosts/"$(hostname -s)".nix
$EDITOR nix/hosts/"$(hostname -s)".nix      # set `user`

home-manager switch --flake .#"$(hostname -s)"
```

That installs the 27 tools into `~/.nix-profile`, puts them on `PATH`, and
deploys every config file listed in `nix/lib/deploy.nix`.

Two things that used to be separate steps and now are not:

- **`git` is already there.** It is a nixpkgs attribute and part of the tool
  set, because jj, jjui, lazygit and workmux all shell out to it.
- **No bootstrap step.** `mise bootstrap` existed because mise could not
  install per-user tools and apt packages in one go; home-manager does both.

If you ever want to check what the switch *would* do:

```sh
home-manager build --flake .#"$(hostname -s)"    # build the profile without activating it
home-manager diff  --flake .#"$(hostname -s)"    # what activation would change
```

After the first switch, open a new shell. If the tools are not found, the
tracked `bashrc` has not been reached yet — check that `~/.bashrc` is the one
from this repo, and that it prepends `~/.nix-profile/bin` to `PATH`.

Set nvim as git's default editor if you like:

```sh
git config --global core.editor nvim
```

## The sandbox

Nothing above is required for the sandbox; the sandbox is required for nothing
above. To run it:

```sh
bin/sandbox ca          # mint the sandbox CA (idempotent)
bin/sandbox link        # link the quadlet units into ~/.config/containers/systemd
bin/sandbox up          # build the images with nix, load them, start everything
bin/sandbox check       # acceptance checks
```

Requirements beyond the above:

| Requirement | Why |
| ----------- | --- |
| cgroup v2 | Quadlet requires it: `podman info --format '{{.Host.CgroupsVersion}}'` should print `v2` |
| a systemd user session | the units are user units; `systemctl --user` must work |
| subuid/subgid | rootless podman: `podman info` should not complain about `newuidmap` |

## Notes and troubleshooting

| Symptom | Cause / fix |
| ------- | ----------- |
| `nix: command not found` in a new shell | The profile is not on `PATH`. The tracked `bashrc` adds `~/.nix-profile/bin`; make sure it is the one being sourced. Or `nix profile install nixpkgs#nix`. |
| `home-manager: command not found` | It is a flake input, not a global: `nix run nixpkgs#home-manager -- switch --flake .#<host>`, or `nix profile install home-manager`. |
| A tool in the repo is not on `PATH` | Check the attribute name in `nix/lib/tools.nix` — five of them are not what mise called them (`jj` is `jujutsu`, `yq` is `yq-go`, …). See [`nix/README.md`](../nix/README.md). |
| An edit in `$HOME` does not reach the repo | Files are **copied**, not symlinked — a symlink into the read-only nix store could not be edited at all. Edit `nix/configs/files/<path>` and re-run `home-manager switch`. |
| A file appears in `$HOME` that the repo does not have | Expected: tools write there (`ya pkg`, pi's `auth.json`, workmux rewriting its config). Those files are yours, not the repo's. |
| `bat` shows its default theme | The theme cache is stale or missing: run `bat cache --build`. The devbox image no longer needs this — its theme is a file in the image, not a compile step. |
| Colours look washed out or 256-colour approximated in `pi`/`jjui`/`opencode`/`leaf` | The terminal does not advertise truecolour (`COLORTERM` unset, `TERM=xterm-256color`). `bashrc` exports `COLORTERM=truecolor`; make sure the shell sources this `bashrc` and the tool inherits it. |
| `eza` shows dircolors colours, not Catppuccin Frappé | `LS_COLORS` is overriding the theme — `bashrc` unsets it, so make sure your shell actually sources this `bashrc`. |
| `workmux` rewrites `~/.config/workmux/config.yaml` and the repo is unchanged | Expected, and the reason config is copied rather than symlinked: workmux rewrites its own config when you cycle the dashboard theme. Put the change in `nix/configs/files/workmux/config.yaml` to make it stick. |

## What gets deployed where

One table, [`nix/lib/deploy.nix`](../nix/lib/deploy.nix), used by both the host
and the devbox image:

| Target                        | Source                          |
| ----------------------------- | ------------------------------- |
| `~/.bashrc`                   | `nix/configs/files/bashrc`      |
| `~/.config/atuin/config.toml` | `nix/configs/files/atuin/config.toml` |
| `~/.config/bat/…`             | `nix/configs/files/bat/…`       |
| `~/.config/eza/theme.yml`     | `nix/configs/files/eza/theme.yml` |
| `~/.config/hunk/config.toml`  | `nix/configs/files/hunk/config.toml` |
| `~/.config/jjui/…`            | `nix/configs/files/jjui/…`      |
| `~/.config/lazygit/config.yml` | `nix/configs/files/lazygit/config.yml` |
| `~/.config/leaf/…`            | `nix/configs/files/leaf/…`      |
| `~/.config/opencode/cli.json` | `nix/configs/files/opencode/cli.json` |
| `~/.config/opencode/opencode.json` | `nix/configs/files/opencode/opencode.json` |
| `~/.config/procs/config.toml` | `nix/configs/files/procs/config.toml` |
| `~/.config/starship.toml`     | `nix/configs/files/starship.toml` |
| `~/.config/workmux/config.yaml` | `nix/configs/files/workmux/config.yaml` |
| `~/.config/yazi/…`            | `nix/configs/files/yazi/…`      |
| `~/.config/zellij/config.kdl` | `nix/configs/files/zellij/config.kdl` |
| `~/.pi/agent/…`               | `nix/configs/files/pi/…`        |

`nix/configs/files/sshd/sshd_config` is the exception: it is deployed into the
devbox **image** only, and the host table deliberately omits it.