# Usage

How to change a config file, and how to change a tool.

## Edit a config file

Config sources live in `nix/configs/files/`; the table in
[`nix/lib/deploy.nix`](../nix/lib/deploy.nix) says where each one goes.

```sh
cd ~/src/dotfiles
$EDITOR nix/configs/files/zellij/config.kdl
home-manager switch --flake .#"$(hostname -s)"
```

Three commands, and it is the same three every time. Before switching:

```sh
home-manager diff  --flake .#"$(hostname -s)"   # what activation would change
home-manager build --flake .#"$(hostname -s)"   # build the profile without activating
```

**The files in `$HOME` are copies, not symlinks.** That is deliberate: a symlink
into `/nix/store` is read-only, and `nvim ~/.config/zellij/config.kdl` has to
work. The consequence is the one git already has about a tracked file — an edit
in `$HOME` is not an edit to the source, and the switch will overwrite it. Edit
the source, not the target.

Files that a tool writes itself (`~/.config/yazi` additions, pi's `auth.json`,
workmux's config when you cycle its dashboard theme) are yours, not the repo's,
and a switch leaves them alone because they are not in the table.

## Add a config file

1. Put the file in `nix/configs/files/`, under the tool's folder if it has one
   (`nix/configs/files/<tool>/<name>`).
2. Add it to [`nix/configs/default.nix`](../nix/configs/default.nix) — one line,
   `f "<tool>/<name>"`.
3. Add the target to [`nix/lib/deploy.nix`](../nix/lib/deploy.nix) — the table is
   `source -> path relative to $HOME`.
4. Switch.

The image picks it up for free: `nix/images/devbox.nix` deploys the same table,
plus `imageOnly` for the files that must never reach a host.

## Remove a config file

Delete the source, both lines above it, and run a switch. If the file is the
devbox's `sshd_config`, remember it is in `imageOnly`, not `targets`.

## Add a tool

Tools are nixpkgs attributes in
[`nix/lib/tools.nix`](../nix/lib/tools.nix), as an **attrset**:

```nix
tools = {
  ripgrep = ripgrep;
  # ...
};
```

Two things to know before you write one:

- **Check the attribute name.** Five of the 27 are not what their command is
  called — `jj` is `jujutsu`, `yq` is `yq-go`, `leaf` is
  `leaf-markdown-viewer`, `pi` is `pi-coding-agent`, `node` is `nodejs_22`. A
  name that looks right can be a different program entirely: nixpkgs' `jj` is a
  JSON stream editor. Confirm against the package's `description` and
  `homepage`, not its name.
- **If it is not in nixpkgs**, it becomes a flake input rather than a package
  (`workmux` is). `flake.lock` pins it either way.

Adding a tool that should only be in the devbox image: put it in `image`, not
`host` — see the `openbao` comment there.

Then `home-manager switch`.

## Upgrade a tool

```sh
nix flake update nixpkgs        # bumps every pinned version
nix flake update nixpkgs home-manager
home-manager switch --flake .#"$(hostname -s)"
```

The versions are in `flake.lock`, which is the point: `mise` had every tool on
`latest` with no lock file, so an upgrade was whatever happened to be published
that day.

For the sandbox images, a version bump is a rebuild:
`bin/sandbox build && systemctl --user restart sandbox-ingress`.

## Update the devbox image

```sh
bin/sandbox build              # nix build + podman load, for all three images
systemctl --user restart sandbox-devbox
```

A rebuild bakes a **new sshd host key** — expect the client to complain about a
changed fingerprint and drop the stale `[127.0.0.1]:2222` line from
`~/.ssh/known_hosts`.

## Shell history (atuin)

`~/.config/atuin/config.toml` is managed here, so the settings are versioned.
Atuin runs in **local-only** mode (`auto_sync = false`, no sync login): history
is kept in the SQLite database at `~/.local/share/atuin/history.db`, which is
not tracked by this repo. The bash key binding (Ctrl-R) comes from
`eval "$(atuin init bash)"` in the tracked `bashrc`.

To sync between machines, use `atuin login` — the shared history mise used to
provide through `mise dot save`/`origin` is not part of this repo's setup, and
nothing here depends on it.

## Sandbox

Covered in [Sandbox](./sandbox.md). The commands you will use most:

```sh
bin/sandbox up            # link, build, start everything
bin/sandbox check         # acceptance checks
bin/sandbox shell         # a shell in the devbox
bin/sandbox logs egress   # follow one service
bin/sandbox rules egress  # the ruleset the controller would install
bin/sandbox down          # stop
```

After editing a unit in `sandbox/quadlet/`, `bin/sandbox link` and restart that
one unit — no rebuild.