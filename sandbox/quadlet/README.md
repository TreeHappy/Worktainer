# Quadlet units

The sandbox's definition: three networks, three volumes and seven containers, in
files systemd understands. This replaces `../compose.yaml` (276 lines),
`../bin/networks` (79 lines) and the hand-maintained ordering between them.

`bin/sandbox link` symlinks each file into `~/.config/containers/systemd/`, then
`systemctl --user daemon-reload` turns them into services. Nothing else is
required: a `.container` that says `Network=sandbox-data.network` gets an
automatic `Requires=` and `After=` on `sandbox-data-network.service`, so
`bin/sandbox up sandbox-devbox.service` brings up the networks it needs, in
order, without anyone having said so.

The units carry their own comments. What is here is the map, the decisions that
are not obvious from a file, and what has not been tested.

## Layout

| File | What it is |
| ---- | ---------- |
| `sandbox-{ctrl,data,wan}.network` | the three networks, one `podman network create` each |
| `{o11ylite-data,otel-desktop-viewer-data,otelop-data}.volume` | the three telemetry stores |
| `sandbox-ingress.container` | the only way in |
| `sandbox-egress.container` | the only way out |
| `sandbox-devbox.container` | the devbox and its sshd |
| `sandbox-openbao.container` | secrets, read by exactly two clients |
| `sandbox-telemetry-*.container` | three span stores, so the same spans can be compared |
| `environments/*.env` | one env file per service, read by the unit and by `bin/sandbox rules` |

`Image=` for the three images nix builds, by the tags `bin/sandbox build`
loads — a tag is enough there, because the content *is* the lockfile. The other
four containers are upstream images, and they are pinned **by digest**: a tag
would let a `bin/sandbox up` months from now pull different code than the stack
was designed against, with no signal (audit S3). Each unit says how to move its
digest on purpose.

## Four things that are not obvious

**`IP=` is the wrong key, and four of the seven containers need per-network
addresses.** Quadlet's `IP=` is a bare `podman run --ip`, which podman applies
to a single network. `Network=` passes its value straight through to
`--network`, so the address rides along with the network it belongs to:

```
Network=sandbox-data.network:ip=10.89.1.2
```

becomes `--network sandbox-data:ip=10.89.1.2` plus the ordering. A mechanical
translation of the compose file would build and then fail to start.

**`NetworkName=` on every network, so the names stay `sandbox-*`.** Without it
Quadlet calls each one `systemd-<file>`, and `.network` references resolve to
the *resource* name — so naming them keeps both the stable names and the
ordering guarantee. They also still have to be named, because the ingress DNATs
to bare IPs and `bin/check` knows them.

**`--route` has no key, and `PodmanArgs=` is not a workaround.** The generated
`podman network create` has no route argument at all, so `PodmanArgs=` is the
only spelling available — and it is a supported key on `[Network]`, not an
escape hatch. One line in `sandbox-data.network`, and the property the whole
sandbox exists to provide is written down.

**`Requires=` is not what `depends_on:` meant.** compose's `depends_on` means
"start this first"; systemd's `Requires=` also means "fail if this fails". So
the ingress `Wants=` the three telemetry backends (its DNAT rules install
whether or not a UI is listening) and `Requires=` OpenBao, whose absence would
leave the proxy with no secrets to inject.

## The env files

One per service, in `environments/`, read by the unit through
`EnvironmentFile=` **from `[Container]`** — in `[Service]` systemd would read it
into the `podman` process instead of passing it to the container.

Relative paths work because Quadlet calls `EvalSymlinks` on every entry it
finds in a search directory, so a symlinked unit's own directory is the
checkout.

Two conventions, both because systemd env files cannot hold what compose could:

- **Values with spaces are quoted.** systemd, podman's `--env-file` and the
  shell all agree on `KEY="value"`. Unquoted, `bin/sandbox rules` — which reads
  the same file with the shell — would run the second word as a command.
- **`HEADER_JOBS` is semicolon-separated**, one job per secret, because an env
  file cannot hold a newline. See `parse_jobs` in `../egress/auth_inject.py`.

The point of reading the same file in both places: `bin/sandbox rules` prints
the ruleset the container would actually install, not the entrypoint's copy of
the defaults. Both rulesets were checked against a real kernel with the repo's
own `unshare -rn nft -c` trick.

## Hardening folded in

From `todo/security-audit.md` and `todo/compare/06-workload-and-isolation.md`,
added while the files were open:

- `PublishPort=127.0.0.1:…` on all six published ports (S5). Nothing outside
  the host reaches them, and binding all interfaces put OpenBao — fixed root
  token, no seal — on the LAN.
- `NoNewPrivileges=true` everywhere, and `DropCapability=` on all seven: the
  two controllers keep only `CAP_NET_ADMIN`/`CAP_NET_RAW`, the other five drop
  everything.
- `PidsLimit=` and `Memory=` on all seven.

## Gotchas carried over from the todo

1. **`ContainerName=` on all seven.** Without it Quadlet names each container
   `systemd-sandbox-<service>` and every `podman exec sandbox-*` in
   `../bin/check` and `../bin/sandbox` breaks.
2. **`Restart=always` in `[Service]`** — it is not a `[Container]` key, so
   writing it there fails generation as an unknown key. It differs from
   `unless-stopped` on a clean exit: systemd restarts, podman would not. The
   egress is where it matters, since it exits non-zero on purpose when its proxy
   dies.
3. **`CgroupsMode` defaults to `split`**, not podman's `enabled`. Fine at these
   limits; it is the first thing to look at if a `Memory=` is ever exceeded and
   the unit does not react.
4. **cgroup v2 is required** — check `podman info --format
   '{{.Host.CgroupsVersion}}'` before the first `up`.
5. **`TimeoutStartSec=900`**, because a cold start pulls an image and systemd's
   90-second default is not much for that.
6. **Drop-ins still work.** `~/.config/containers/systemd/sandbox-ingress.container.d/`
   survives a re-link, because `bin/sandbox link` links files rather than the
   directory.
7. **`bin/sandbox rules` needs neither a container nor systemd** — it sources
   the env file and runs the entrypoint with `DRY_RUN=1`.

## What was verified, and what was not

**Verified here**, without starting a container:

- Every claim above was read out of podman 5.7's implementation
  (`pkg/systemd/quadlet/quadlet.go`) and `podman-systemd.unit(5)` rather than
  assumed; the table in the previous revision of this file listed which function
  answers which question.
- `bin/sandbox rules` renders both controllers' rulesets from the env files,
  and both validate against a real kernel (`unshare -rn nft -c`), with the proxy
  both armed and unarmed.

**Not verified**: no container was started. This box cannot start rootless
containers (`newuidmap: write to uid_map failed` — a nested userns) and has no
systemd user session, so the units were never generated or started. On a host
that can:

```sh
bin/sandbox link && bin/sandbox up
podman network inspect sandbox-data | grep -A5 Route   # the --route, for real
systemctl --user status 'sandbox-*'
```