# Quadlet units — outline

The units that replace `../compose.yaml`. They are declared here, in the repo,
and linked into `~/.config/containers/systemd/` by `bin/sandbox`, so the source
of truth stays one place and a `systemctl --user daemon-reload` picks up an edit
without a rebuild.

**This directory is an outline.** The layout, the key mapping and the resolved
questions below are settled and cited; the unit bodies are not written yet. Work
through *Conversion order* at the bottom.

Everything here was read out of podman 5.7's Quadlet implementation, not from
habit — see *Verification* at the end for the sources.

## Layout

```
sandbox/quadlet/
  sandbox-ctrl.network          control plane, no default route
  sandbox-data.network          devbox network, default route via the egress
  sandbox-wan.network           the egress's uplink, metric=100
  sandbox-ingress.container     the way in
  sandbox-egress.container      the way out
  sandbox-devbox.container      the devbox and its sshd
  sandbox-openbao.container     secrets, read by two clients
  sandbox-telemetry-o11ylite.container
  sandbox-telemetry-otel-desktop-viewer.container
  sandbox-telemetry-otelop.container
  o11ylite-data.volume
  otel-desktop-viewer-data.volume
  otelop-data.volume
  environments/                 one .env per service, the single source of values
```

File names are the systemd unit names: `sandbox-egress.container` becomes
`sandbox-egress.service`, `sandbox-ctrl.network` becomes
`sandbox-ctrl-network.service`.

`NetworkName=` and `VolumeName=` are set explicitly on every network and volume,
so the podman resources keep the `sandbox-*` names the rest of the tooling
already expects. Without it Quadlet would name each one `systemd-<file>`.

## How the units reach systemd

Rootless Quadlet reads four directories; the one a per-user checkout belongs in
is `$XDG_CONFIG_HOME/containers/systemd/`. Quadlet follows symlinks both as the
search-path entry and inside it, so `bin/sandbox` links each unit file
individually:

```sh
ln -s "$repo/sandbox/quadlet/sandbox-egress.container" \
      ~/.config/containers/systemd/sandbox-egress.container
systemctl --user daemon-reload
```

Two links per surface rather than one directory symlink, so a drop-in
(`sandbox-ingress.container.d/10-override.conf`) can live in `~/.config` and
survive a re-link.

The env files sit next to the units and are referenced **relatively**
(`EnvironmentFile=environments/egress.env`). `EnvironmentFile=` is resolved
against the unit file's own directory, and Quadlet calls `EvalSymlinks` on every
entry it finds in a search directory — so for a symlinked unit that directory is
the checkout, not `~/.config`. The relative path lands in the repo, which is
what makes this work at all. An absolute path here would have to name the
checkout, which is exactly the thing a tracked file must not do.

## What maps to what

| `compose.yaml` | Quadlet | Note |
| -------------- | ------- | ---- |
| `networks: {…external}` + `bin/networks` | `*.network` | options that were CLI flags |
| `container_name` | `ContainerName=` | **required** — see gotchas |
| `hostname` | `HostName=` | |
| `networks: {n: {ipv4_address}}` | `Network=n.network:ip=…` | **not** `IP=` — see below |
| `ports:` | `PublishPort=` | |
| `cap_add:` | `AddCapability=` | |
| `sysctls:` | `Sysctl=` | |
| `dns:` | `DNS=` | |
| `environment:` | `EnvironmentFile=` | |
| `volumes:` (named) | `*.volume` + `Volume=n.volume:/data` | auto-created, auto-ordered |
| `volumes:` (bind) | `Volume=./ca:/etc/sandbox/ca:ro` | a leading `.` is what makes the source unit-relative |
| `depends_on:` | `[Unit] Requires=` + `After=` | or `Wants=` — see below |
| `restart: unless-stopped` | `[Service] Restart=always` | |
| `command:` | `Exec=` | |
| `build:` | *(gone — Nix builds the images)* | `Image=` |

### `IP=` is the wrong key here, and `Network=` carries the address

This is the one place a mechanical translation produces something that builds
and then cannot start. Quadlet's `IP=` maps to a bare `podman run --ip`, which
applies to one network; four of the seven containers are on two or three.
Quadlet's `Network=` instead passes its value through to `--network`, so the
network's own `name:option=…` syntax is available and the address rides along
with the network it belongs to:

```
Network=sandbox-ctrl.network:ip=10.89.0.2
Network=sandbox-data.network:ip=10.89.1.2
Network=sandbox-wan.network:ip=10.89.2.2
```

which becomes three `--network` arguments, each carrying its own address, plus
`Requires=`/`After=` on each `*-network.service`. That is the same argument list
`podman-compose` generates today.

### `Requires=` or `Wants=`

`depends_on` in compose means "start this first" and nothing more — a container
that fails to start does not take its dependents down with it. systemd's
`Requires=` does. So:

- `Wants=` + `After=` where compose only meant ordering: the ingress on the
  three telemetry backends. The DNAT rules are installed regardless of whether
  a telemetry UI is listening.
- `Requires=` + `After=` where the dependency is load-bearing: the devbox on the
  egress, the ingress and OpenBao. Without the egress the devbox has no route;
  without OpenBao its `sshd-init` has nowhere to fetch keys from.

## The three networks

Each is one file, and each reproduces one `podman network create` from
`../bin/networks` exactly:

| Unit | `Subnet=` | `Options=` | `DisableDNS=` | `PodmanArgs=` |
| ---- | --------- | ---------- | ------------- | ------------- |
| `sandbox-ctrl.network` | `10.89.0.0/24` | `no_default_route=1` | `true` | — |
| `sandbox-data.network` | `10.89.1.0/24` | `no_default_route=1` | `true` | `--route=0.0.0.0/0,10.89.1.2,1000` |
| `sandbox-wan.network` | `10.89.2.0/24` | `metric=100` | `true` | — |

`--route` has no key of its own; `PodmanArgs=` is the documented escape hatch
and is the only use of it here. See *The `--route` question* below.

The generated service runs `podman network create --ignore`, so re-running it
against an existing network is a no-op rather than an error — the same
tolerance `podman network exists` gave `bin/networks`. `NetworkDeleteOnStop=true`
on all three is what makes `bin/sandbox clean` a single `systemctl --user stop`.

## The seven containers

Common to all of them: `Image=` (Nix-built by the time this lands),
`ContainerName=sandbox-<service>`, `[Service] Restart=always`,
`TimeoutStartSec=900`, and the hardening block below.

| Unit | Networks | Publishes | Notes |
| ---- | -------- | --------- | ----- |
| `sandbox-ingress` | ctrl `.3`, data `.3` | 2222, 8080, 8200, 9419-9421 | `AddCapability=CAP_NET_ADMIN CAP_NET_RAW`, `Sysctl=net.ipv4.ip_forward=1`, `DNS=9.9.9.9`, `Wants=` the three telemetry units |
| `sandbox-egress` | ctrl `.2`, data `.2`, wan `.2` | — | as ingress, plus `Requires=` OpenBao and the read-only CA bind mount |
| `sandbox-devbox` | data `.10` | — | `DNS=10.89.1.2`, `Exec=` the `sshd-init && exec sshd -D -e` sequence, `User=dev` |
| `sandbox-openbao` | data `.20` | — | no capability, no limit. The root token is in `environments/openbao.env`, tracked — exactly as it is in `compose.yaml` today, and for the same reason (audit S1) |
| `sandbox-telemetry-o11ylite` | ctrl `.20` | — | volume-backed `/data` |
| `sandbox-telemetry-otel-desktop-viewer` | ctrl `.21` | — | `Exec=` its CLI flags, DuckDB on the volume |
| `sandbox-telemetry-otelop` | ctrl `.22` | — | volume-backed `/data` |

The two controllers are the only containers that need a capability or a sysctl;
the other five get neither, which is the default and worth stating.

### Environments

One `environments/<service>.env` per service, referenced by
`EnvironmentFile=environments/<service>.env` from `[Container]` — not
`[Service]`, where systemd would read it into the `podman` process instead of
passing it on. The file is a plain `KEY=value` list with no quoting, so it reads
identically as a systemd env file, as a `--env-file`, and as a shell `set -a;
.` — which is what lets `bin/sandbox rules` render exactly the ruleset the
container would install, instead of the entrypoint's copy of the defaults.

That is the whole of step 7 in `todo/quadlet.md`: the `: "${VAR:=default}"`
lines come out of both entrypoints once the env file is authoritative, and
`compose.yaml` stops being a second copy.

## Hardening folded in

The isolation findings in `todo/compare/06-workload-and-isolation.md` and audit
S5, added while the files are open:

- `PublishPort=127.0.0.1:…` on all six published ports. Nothing outside the host
  reaches them today, and binding all interfaces put OpenBao — fixed root token,
  no seal — on the LAN.
- `NoNewPrivileges=true` on the five containers that need no capabilities.
- `DropCapability=ALL` on those same five.
- `PidsLimit=` and `Memory=` on all seven.

None of this applies to the two controllers: `NET_ADMIN` is what makes them
controllers.

## Resolved gotchas

1. **`ContainerName=` on all seven.** Without it Quadlet names each container
   `systemd-sandbox-<service>` and every `podman exec sandbox-*` in
   `../bin/check` and `../bin/sandbox` breaks.
2. **`Restart=always`, not `unless-stopped`** — and it goes in `[Service]`.
   `Restart` is not a `[Container]` key, so writing it there fails generation as
   an unknown key. The two differ on a clean exit: systemd restarts a container
   that exited 0, podman's `unless-stopped` does not. `systemctl --user stop`
   still wins in both cases. The controllers are where it matters — the egress
   exits non-zero deliberately when its proxy dies, and the restart policy is the
   intended recovery.
3. **`CgroupsMode` defaults to `split`.** Fine at today's limits; if a
   `Memory=` is ever exceeded and the unit does not react as expected, this is
   the first thing to look at.
4. **cgroup v2 is required.** Check it before starting, since nothing here can:
   `podman info --format '{{.Host.CgroupsVersion}}'`.
5. **`TimeoutStartSec=900`** for a cold start that pulls an image.
6. **`bin/sandbox rules` keeps working with no container and no systemd.** It
   reads `environments/<service>.env` and runs the entrypoint with `DRY_RUN=1`.
7. **`podman-compose` was only ever used by `bin/sandbox`**, never by
   `bin/check`, so dropping it drops `apt:podman-compose` from `[bootstrap]`.

## The `--route` question

The todo gated the whole migration on whether a `.network` unit can express the
data network's default route. It can, and the probe is no longer needed.

`podman network create` in a `.network` unit is assembled from a fixed key list:
`--disable-dns`, `--internal`, `--ipv6`, `--driver`, `--ipam-driver`,
`--interface-name`, `--dns`, `--subnet`/`--gateway`/`--ip-range`, `--opt`,
`--label`, and then whatever `PodmanArgs=` holds, and finally the network name.
There is no route key, and no `--route` anywhere in the generator — so the
escape hatch is the only way, and it is a first-class supported key on
`[Network]`, not a hack.

The data network therefore needs one `PodmanArgs=` line and nothing else
unusual. The fallback the todo feared — keeping a reduced `bin/networks` alive
for one route — does not apply.

## Verification

This box cannot start rootless containers (`newuidmap: write to uid_map failed`
— nested userns), so nothing here was executed. What *was* done is read directly
out of the implementation and the shipped documentation for the exact version
being targeted:

| Question | Source |
| -------- | ------ |
| `[Network]` key list, and that it is exhaustive | `groupsInfo[NetworkGroup].SupportedKeys` in `pkg/systemd/quadlet/quadlet.go` |
| `--route` is expressible, via `PodmanArgs` | `ConvertNetwork` → `handlePodmanArgs`, same file |
| `Network=x.network` resolves to the resource name and adds `Requires=`/`After=` | `addNetworks`, same file |
| `.network` reference implies the `systemd-` name and a dependency | `podman-systemd.unit(5)`, `Network=` |
| `EnvironmentFile=` resolves relative to the unit file | `getAbsolutePath` called from the `KeyEnvironmentFile` branch |
| …and for a symlinked unit that is the checkout, not `~/.config` | `AppendSubPaths` calls `EvalSymlinks` on every search-dir entry, `unitdirs.go` |
| Resource names default to `systemd-<file>` | `getResourceName`, same file |
| Capabilities are `CAP_`-prefixed and space-separated | `podman-systemd.unit(5)`, `AddCapability=` |

Left to run on a host that can:

```sh
systemctl --user start sandbox-data-network.service
podman network inspect sandbox-data | grep -A5 Route
```

diffed against what `bin/networks` creates today — the step the todo called
step 2.

## Conversion order

1. The three `.network` files, and the inspect-and-diff above.
2. `egress.container` — most environment variables, so the worst case.
3. `ingress.container`, then `openbao`, then the devbox, then the telemetry
   three.
4. The three `.volume` files and the env files.
5. `bin/sandbox` as a `systemctl --user` wrapper, keeping `rules`, `nft`,
   `check`, `exec` and `ca` as they are.
6. The hardening block, while the files are open.
7. Delete `compose.yaml` and `bin/networks`, drop `apt:podman-compose`.

Steps 5-7 land after the images are built by Nix (`todo/nix-migration.md` step
8), where `Image=` has already replaced `build:`.