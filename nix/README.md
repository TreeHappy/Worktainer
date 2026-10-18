# The Nix provisioning layer

Tools, configuration and images, from `flake.nix` at the repo root. `nix build`
produces the images, `podman load` registers them, and Quadlet
([`sandbox/quadlet/`](../sandbox/quadlet/README.md)) starts them.

```sh
nix build .#sandbox-images                 # the three images, as one build
nix build .#sandbox-devbox && podman load < result
home-manager switch --flake .#myhost       # the host
```

The detailed plan is in [`todo/nix-migration.md`](../todo/nix-migration.md). This
is the part worth keeping once the todo is retired: the decisions, and the three
things that turned out harder than the plan said.

## The two decisions, taken

1. **Images are fully Nix.** `nix build .#sandbox-ingress` →
   `podman load`. No `FROM`, no distro, no layer cache — every package and every
   byte of config comes out of a lockfile. The alternative (keep the distro,
   copy a nix closure in) is a smaller change and a smaller guarantee; the ask
   was the lockfile.
2. **Home-manager on the host, nothing host-manager-shaped in the images.** A
   flake plus `nix profile` covers the tools but not the configuration, and the
   `programs.*` modules that manage XDG files are home-manager's. Inside an
   image the config is just files written at build time — no home-manager.

Podman itself stays on apt. Rootless podman from nixpkgs drags in subuid
handling and cgroup setup that is genuinely painful outside NixOS, and nothing
here is blocked by keeping it.

## Layout

```
flake.nix                   at the repo root — it has to be
nix/configs/default.nix     the 27 config sources, read from files/
nix/configs/files/          those sources (every tool's own folder)
nix/lib/tools.nix           the toolchain, as an attrset (see below)
nix/lib/deploy.nix          source -> $HOME target, one entry per file
nix/lib/image.nix           how the images are built
nix/modules/host.nix        the home-manager module
nix/hosts/<hostname>.nix    one per machine: the username, and nothing else
nix/images/{ingress,egress,devbox}.nix
```

`flake.nix` is at the repo root, not inside `nix/`. A flake can only read paths
under its own directory, and the images need `sandbox/ingress/entrypoint.sh` and
`sandbox/ca/` — which are outside `nix/`. That was found by evaluating the flake,
not by reading it.

## The toolchain

mise's `[tools]` held **27** entries, not 28; the devbox's copy held 28 because
it adds `openbao`. Every one was checked against nixpkgs
(`nixos-unstable` @ `fe13242`) by evaluating it. **Of the 27, 21 keep their
attribute name, five resolve to a different one, and one is not packaged at
all.**

The five that move are the ones to read twice — each is a name that resolves to
something real and, in two cases, wrong:

| command | nixpkgs | Why not the same name |
| --------- | ------- | --------------------- |
| `jj` | **`jujutsu`** | nixpkgs `jj` is [tidwall/jj](https://github.com/tidwall/jj), a JSON stream editor. Unrelated. |
| `yq` | **`yq-go`** | nixpkgs `yq` is the Python one; mise's is mikefarah's Go tool |
| `github:RivoLink/leaf` | **`leaf-markdown-viewer`** | renamed upstream, same project (`leaf.rivolink.mg`) |
| `pi` | **`pi-coding-agent`** | renamed upstream, same project (pi.dev) |
| `node` | `nodejs_22` | not `nodejs`: the unqualified attribute is a moving default, so pinning it would defeat the point of pinning |

Only the first two install the wrong tool. The other three are the right tool
under a name the mise list never had to spell.

And one gap:

| command | nixpkgs | Resolution |
| --------- | ------- | ---------- |
| `workmux` | *nothing* | not packaged. It is Rust and [ships its own flake](https://github.com/raine/workmux), so it becomes a flake **input** — pinned by `flake.lock` like everything else, at the cost of tracking upstream |

Everything else is `atuin`, `bat`, `carapace`, `duf`, `dust`, `eza`, `fd`, `fzf`,
`gh`, `hunk`, `jjui`, `jq`, `lazygit`, `neovim`, `opencode`, `openbao`,
`procs`, `ripgrep`, `starship`, `yazi`, `zellij`, `zoxide` — verified
individually, not assumed from the name.

**This forces `modules/tools.nix` to be an attrset, not a list of strings.** A
`map (name: pkgs.${name})` over the mise list gets five of the twenty-seven
wrong, and all five produce a working binary — `pkgs.jj` and `pkgs.yq` both
build, they are just the wrong programs. There is no failure to notice.

Versions at the time of checking, which is what `flake.lock` will freeze:

```
atuin 18.23.0     bat 0.26.1        carapace 1.7.3     duf 0.9.1
dust 1.2.6        eza 0.23.5        fd 10.5.0          fzf 0.74.5
gh 2.102.0        hunk 0.23.0       jjui 0.10.11       jq 1.8.2
jujutsu 0.46.0    lazygit 0.66.1    leaf-markdown-viewer 1.28.3
neovim 0.12.6     nodejs_22 22.23.3 openbao 2.7.1      opencode 1.19.0
pi-coding-agent 1.2.0              procs 0.14.12      ripgrep 15.2.0
starship 1.26.0   yazi 26.9.1       yq-go 4.54.1       zellij 0.45.1
zoxide 0.10.0
```

This closes audit **S4** — every one of those 27 tools was pinned to
`"latest"`, with no lock file.

## Configuration

The load-bearing idea: the 27 files under `nix/configs/files/` are read **once**
and consumed by both sides of the sandbox.

- **Host**: 26 targets, deployed by `nix/modules/host.nix` through
  home-manager, from the table in `nix/lib/deploy.nix`.
- **Devbox**: the same table plus `imageOnly`
  (`~/.ssh/sshd/sshd_config`), copied into `/home/dev` by
  `nix/images/devbox.nix`. No home-manager inside the image — the config is
  fixed at build time, so it is just files.

**Read, not pasted.** The first attempt escaped each file into a Nix `''…''`
string. The tree is TOML, KDL, JSON, YAML and two copies of a 2000-line tmTheme,
and a literal quote next to an interpolation becomes `'''${` — which Nix reads as
an escaped quote pair followed by a *real* interpolation, silently producing a
config with text missing. `nix/configs/default.nix` reads the files instead, and
every one of the 26 host targets was then verified byte-for-byte against the
tracked original through the real evaluator.

The count is uneven: `yazi/` alone is seven (a theme, a config and five flavor
files), `opencode/`, `pi/`, `jjui/`, `leaf/` and `bat/` are two each, and the
rest are one apiece.

The bashrc is the sharp end of this: the whole tree — bashrc, atuin, starship,
zellij, fzf, jjui — is written for bash, and `bash` has to stay bash. Two lines
in it changed for the move: `mise activate` became a `PATH` prepend for
`~/.nix-profile/bin`, and two `[ -x /usr/bin/… ]` probes became
`command -v`, because a nix closure has no `/usr/bin`.

## Images

Three of seven move. The other four are upstream images pinned to `:latest` and
stay as they are — `openbao`, `o11ylite`, `otel-desktop-viewer`, `otelop`. They
sit on the `ctrl` network behind the ingress and are not part of the trust
boundary, so this is a scope boundary rather than an oversight. Say so in the
docs so it does not read as a bug later.

`ingress` and `egress` are ordinary `dockerTools.buildLayeredImage` calls:
everything in them runs as root, which is what a controller wants, and a layered
image is the cheap way to get a podman-loadable tarball out of nixpkgs. Their
package lists are shorter than the Dockerfiles they replace — `otel-cli 0.4.5`
and `mitmproxy 12.2.3` were release-tarball and `pip install` steps with versions
in `ARG` lines, and both are now attributes, at exactly those versions.

The **devbox is the whole risk**, and it needed one thing the other two did not:
a uid-1000 user that *owns* its home. `buildLayeredImage` copies every content
with `rsync --chown=0:0` and tars with `--owner=0 --group=0`, so the whole image
is root's — and sshd refuses to start when the account, its `~/.ssh` and its host
key are not owned by that account. `buildImage` has no ownership mechanism in
this nixpkgs (the evaluator rejects `fakeRootCommands`); `uid = 1000,
gid = 1000` on the layer does it, and the cost is that `/nix` and `/etc` belong
to `dev` too, which is untidy and harmless in an image where nothing runs as
root.

So the devbox's seven problems resolved as:

| | |
| --- | --- |
| a real `dev` at uid 1000 | the layer's owner, plus an `/etc/passwd` entry |
| the CA trust path | built from `cacert`; the sandbox CA is appended at container start |
| sshd's location | unchanged: config and host key under `~/.ssh/sshd`, port 2222 |
| bash as the shell | unchanged, and deliberately: the whole config tree is bash |
| `NODE_EXTRA_CA_CERTS` | still `/etc/ssl/certs/ca-certificates.crt`, which is where nixpkgs puts it |
| `bat cache --build` | gone — the theme is a file, not a compile step |
| the host key | still baked, so a rebuild re-keys. Now generated by the build, so it survives a restart. |

And the recommendation in `todo/nix-migration.md` — "nixpkgs packages on a
minimal base, not a NixOS tarball" — held, but for a narrower reason than the
todo gave. A NixOS tarball was tried first and would have worked (it is the only
thing that handles `users.users` properly), but it pulls in an activation
pipeline and a much heavier evaluation for no benefit here. The one NixOS-shaped
problem the todo predicted is not the one that mattered: activation scripts run
at *build* time in a builder, which is exactly when they should.

## What this settles for free

| Audit item | Settled by |
| ---------- | ---------- |
| S4 — every tool pinned to `latest` | `flake.lock` |
| S2 — CA private key in the devbox image | the CA is never named from nix, so it cannot enter the store |
| S6 — the devbox image did not build | `update-ca-certificates` ran as uid 1000 with no guard; it is gone |
| no capability drops, no resource limits | Quadlet keys, folded in while the units were written |

S2 is worth spelling out because the obvious fix is the wrong one. `.dockerignore`
kept `sandbox/ca/*.key` out of the *build context*; that lever is gone with
Dockerfiles. The structural fix is that `sandbox/ca/` is gitignored, so a flake
cannot see it at all — and naming it would put the key in the store, which lands
in the image. So it is bind-mounted read-only instead, and appended to the trust
store by `sandbox/dev/devbox-init.sh` on every container start. Rotating the CA
is now a container restart rather than an image rebuild.

S1 (root token in the devbox environment) is *not* settled by this and should be
fixed on its own merits.

## Verified, and not

**Verified here**, without building anything:

- All 28 nixpkgs attributes evaluate, at the revision in `flake.lock`.
- All three image derivations evaluate to real `.drv` paths — which is what
  caught `buildImage`'s missing ownership mechanism and the flake-at-`nix/`
  path problem.
- The host configuration deploys 26 config files and 28 packages, and all 26
  were compared byte-for-byte against the tracked originals.

**Not verified**: anything requiring a build. No image was built, no home-manager
switch was run, and no container was started — this box cannot start rootless
containers and has no systemd user session.

The first thing to do on a host that can:

```sh
nix flake check
nix build .#sandbox-ingress && podman load < result
cp nix/hosts/example.nix nix/hosts/"$(hostname -s)".nix   # set `user`
home-manager switch --flake .#"$(hostname -s)"
```
