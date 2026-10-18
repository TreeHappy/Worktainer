# The Nix provisioning layer — outline

Replaces mise for tools *and* configuration, on the host and in the three
containers this repo builds. `nix build` produces the images, `podman load`
registers them, and Quadlet ([`sandbox/quadlet/`](../sandbox/quadlet/README.md))
starts them.

**This directory is an outline.** Both open decisions are taken, the toolchain is
mapped and verified against a real nixpkgs, and the shape below is the proposal.
No `flake.nix` exists yet.

The detailed plan, and the reasoning behind each step, is in
[`todo/nix-migration.md`](../todo/nix-migration.md). This is the part worth
keeping once the todo is retired.

## The two decisions, taken

1. **Images are fully Nix.** `nix build ./nix#sandbox-ingress` →
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
nix/flake.nix            inputs: nixpkgs, plus workmux (see below)
nix/configs/             the 19 config files, written once, read by host + images
nix/modules/tools.nix    the toolchain, as an attrset (see below)
nix/modules/shell.nix    what dotfiles/bashrc becomes
nix/modules/tools/*.nix  one per themed tool
nix/hosts/<hostname>.nix the home-manager entry point
nix/images/{devbox,ingress,egress}.nix
```

Scoped under `nix/` rather than at the repo root as the todo sketched it. The
root already holds eight entries and three of them are documentation; this keeps
the whole migration in one directory that can be moved or dropped as a unit,
which matters while it is being built. `nix build ./nix#sandbox-devbox` from the
repo root, or `nix build` inside `nix/`.

## The toolchain

`[tools]` in `mise.toml` holds **27** entries, not 28; the devbox's copy holds 28
because it adds `openbao`. Every one was checked against nixpkgs
(`nixos-unstable` @ `fe13242`, 2026-10-15) by evaluating it. **Of the 27, 21
keep their attribute name, five resolve to a different one, and one is not
packaged at all.**

The five that move are the ones to read twice — each is a name that resolves to
something real and, in two cases, wrong:

| mise.toml | nixpkgs | Why not the same name |
| --------- | ------- | --------------------- |
| `jj` | **`jujutsu`** | nixpkgs `jj` is [tidwall/jj](https://github.com/tidwall/jj), a JSON stream editor. Unrelated. |
| `yq` | **`yq-go`** | nixpkgs `yq` is the Python one; mise's is mikefarah's Go tool |
| `github:RivoLink/leaf` | **`leaf-markdown-viewer`** | renamed upstream, same project (`leaf.rivolink.mg`) |
| `pi` | **`pi-coding-agent`** | renamed upstream, same project (pi.dev) |
| `node` | `nodejs_22` | not `nodejs`: the unqualified attribute is a moving default, so pinning it would defeat the point of pinning |

Only the first two install the wrong tool. The other three are the right tool
under a name the mise list never had to spell.

And one gap:

| mise.toml | nixpkgs | Resolution |
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

This closes audit **S4** — every one of those 27 tools is currently pinned to
`"latest"`.

## Configuration

The load-bearing idea, and the one that preserves the repo's existing
single-source property: the 19 files under `dotfiles/` are written **once**, as
Nix literals in `modules/tools/*.nix`, and consumed by both the host
(home-manager symlinks or copies into `$HOME`) and the images (files written at
build time). Today `mise.toml` and `dotfiles/` provide that; after this,
`nix/configs/` does.

- **Host**: 16 targets, deployed by home-manager.
- **Devbox**: those 16 plus `~/.ssh/sshd/sshd_config`, written into the image.
  No home-manager inside the image — the config is fixed at build time, so it is
  just files.

Convert one tool first and diff the generated file against the tracked one
before deleting anything. The tracked files are the reference; they are what the
migration is checked against, and the day they are gone is the day this stops
being verifiable.

The bashrc is the sharp end of this: the whole `dotfiles/` tree — bashrc, atuin,
starship, zellij, fzf, jjui — is written for bash, and `bash` has to stay bash.
`modules/shell.nix` is that file plus whatever replaces `mise activate`.

## Images

Three of seven move. The other four are upstream images pinned to `:latest` and
stay as they are — `openbao`, `o11ylite`, `otel-desktop-viewer`, `otelop`. They
sit on the `ctrl` network behind the ingress and are not part of the trust
boundary, so this is a scope boundary rather than an oversight. Say so in the
docs so it does not read as a bug later.

`ingress` and `egress` are the easy ones and go first: `nft`, `tc`, `ip`,
`dnsmasq`, `mitmdump` and `python3` are ordinary nixpkgs packages, and a nix
closure pins better than Alpine's package manager ever did.

The **devbox is the whole risk** and goes last. It is a developer's
environment — bash, an editor, a multiplexer, a VCS client, an sshd — and
everything that makes it useful is bash- and `$HOME`-shaped. Seven specific
problems are listed in the todo; the two that decide the approach:

- **A real `dev` at uid 1000** that sshd will accept. `useradd` today; a
  userset declaration under NixOS. sshd refuses to start without it.
- **The CA trust path.** `update-ca-certificates` into
  `/usr/local/share/ca-certificates` is a Debian convention. Under nixpkgs on a
  minimal base it still works, which is the argument for not going full NixOS.

Recommendation, unchanged: nixpkgs packages on a minimal base, not a NixOS
tarball. A NixOS container expects systemd as PID 1 and manages `/etc` through
activation scripts that do not run in a container — that makes all seven devbox
problems harder for a guarantee nobody asked for.

## Staging

Keep `podman build` alive until near the end. Nothing before the last step
should leave the stack unable to boot.

1. ~~Decide the two columns~~ — done.
2. ~~Prove the Quadlet `--route` question~~ — done, see
   [`sandbox/quadlet/README.md`](../sandbox/quadlet/README.md).
3. **Empty flake** reproducing the 27 tools as the attrset above. Check the set
   one for one against `[tools]`.
4. **`ingress` and `egress`**, which proves the whole image-build path.
5. **Config modules**, one tool at a time, diffed against `dotfiles/`.
6. **Home-manager on the host.** Tools first, config second.
7. **The devbox**, against its seven problems, image building between each.
8. **Delete mise** — `mise.toml`, `sandbox/dev/mise.toml`, the `[dotfiles]`
   section, `dotfiles/`, and the mise init lines from the bashrc.
9. **Quadlet steps 2-7**, with `Image=` replacing `build:`.

## What this settles for free

| Audit item | Settled by |
| ---------- | ---------- |
| S4 — every tool pinned to `latest` | `flake.lock` |
| S2 — CA private key in the devbox image | the new build path, provided the exclusion is set there |
| no capability drops, no resource limits | Quadlet keys, folded in while the units are written |

S2 is the one to watch: `.dockerignore` stops applying the moment images stop
being built by podman, so the exclusion has to be re-established in whatever
build path replaces it. S1 (root token in the devbox environment) and S5
(ports on all interfaces) are not absorbed by this and should be fixed on their
own merits.

## Verified, and not

**Verified here**: every one of the 28 nixpkgs attributes above evaluates, at
the revision quoted — the check built a `buildEnv` over all of them and read the
derivation path. The four remappings were confirmed against each package's
`description`/`homepage` in `package.nix`, not by name; `workmux`'s absence was
confirmed against the `pkgs/by-name` listing, and its flake confirmed upstream.

**Not verified**: anything requiring a build, a container, or a host session.
That is all of the image work, all of home-manager, and the whole of Quadlet.