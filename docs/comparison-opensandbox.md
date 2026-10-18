# Worktainer and OpenSandbox

A comparison of this repository's sandbox against
[OpenSandbox](https://github.com/opensandbox-group/OpenSandbox), the sandbox
*platform* for AI agents. This is not a bake-off — the two solve overlapping
problems at very different scales — but they overlap more than their sizes
suggest, and the overlap is worth writing down.

Both build the same three things:

- **a controlled way in** to the agent's environment,
- **a controlled way out**, including injecting credentials the agent must never
  hold,
- **an isolation boundary** between the agent and the host.

OpenSandbox does it as a product with an API, five SDKs and a Kubernetes
controller. This repository does it as a single podman stack with one devbox in
it. Below: what each one actually does, where they meet, where they diverge, and
which of OpenSandbox's ideas are worth carrying over.

## The two projects at a glance

| | Worktainer (this repo) | OpenSandbox |
| --- | --- | --- |
| What it is | one sandbox for one agent, plus the network around it | a platform: an API, a server, and many sandboxes |
| Sandboxes | exactly one, fixed at `10.89.1.10` | N, created and destroyed through an API |
| Orchestrator | `podman-compose` + a shell driver, rootless | Kubernetes (`BatchSandbox`, `Pool`, `SandboxSnapshot` CRDs) or Docker |
| How you talk to it | `bin/sandbox shell`, `ssh -p 2222` | SDKs (Python, JS/TS, Kotlin, C#, Go), the `osb` CLI, an MCP server, the REST API |
| Workload image | your own `dotfiles/`, built by mise | any image; official code-interpreter / browser / desktop images |
| Isolation | runc, unprivileged `dev` user, no sudo, no escalation path | runc, gVisor, Kata (QEMU / Firecracker / Cloud Hypervisor), Firecracker microVMs |
| Runtime footprint | ~1,565 lines of shell, Python and Dockerfiles under `sandbox/` | a Python server, Go `execd`/`ingress`/`egress`/`node-agent`, a K8s controller |
| License | MIT | Apache-2.0 |
| Governance | one maintainer | OpenSSF Best Practices, CNCF Landscape, Cosign-signed images with provenance |
| Maturity | each component validated against the real thing, the stack never booted end to end | CI, an E2E status badge, nightly Kubernetes builds |

The last row is the one to keep in mind while reading the rest: the sandbox in
[`sandbox/README.md`](../sandbox/README.md) is a working *design* whose pieces
have each been checked against real components — nftables rulesets against a
real kernel, the mitmproxy addon against a real proxy, `sshd` against a real
`OpenBao` — but which has never been run as a whole.

## Where they meet

Component for component, the resemblance is close enough to be worth mapping —
and each mapping is also where the differences live.

| Concern | Worktainer | OpenSandbox |
| --- | --- | --- |
| Way in | `sandbox-ingress`: `nft` prerouting DNAT from a `FORWARDS` list, postrouting masquerade to pin the reply path | `components/ingress`: L7 HTTP/WebSocket reverse proxy, header mode or URI mode, optional signed route tokens |
| Way out | `sandbox-egress`: the devbox's default gateway — masquerade, dnsmasq, tbf/netem shaping, nft byte counters | `components/egress`: a sidecar sharing the sandbox's network namespace — DNS filtering and nftables packet enforcement |
| Credential injection | `sandbox/egress/auth_inject.py`: a mitmproxy addon that sets headers whose values are read from OpenBao | Credential Vault, implemented by the same egress sidecar, injected through the mitmproxy MITM listener |
| The CA | `bin/sandbox ca`: EC P-256 root, generated per machine, **baked into the devbox image** | the sidecar exports its CA; sandbox bootstrap installs it into system, NSS and JDK trust stores |
| Secrets server | `sandbox/openbao`: a real OpenBao container in dev mode, on the data network | no vault server — the credential store *is* the egress sidecar's memory |
| Telemetry | `otel-cli` emitting one `net.counters` span per interval to **three** backends | OTLP/HTTP metrics from server, controller, `execd`, egress, ingress and node agent |
| Access to the devbox | sshd on `:2222`, authorized keys fetched from OpenBao at boot | API key on the server, optional `X-EXECD-ACCESS-TOKEN`, endpoint headers or signed route tokens |
| Checks | `bin/sandbox check` — PASS/FAIL/SKIP per item | E2E suites, real-Vault acceptance records, a `troubleshoot-sandbox` agent skill |

The credential-injection row is the striking one. Both decrypt the agent's
outbound TLS and put a credential on the request that the agent never held.
OpenSandbox's docs describe the threat model in almost the same words this repo
uses: a prompt-injected agent should not be able to read a real key back out of
its own environment or its own requests. Two projects, same instinct, same
mitmproxy.

## Where they differ

### Worktainer's egress is a measurement point, not a policy point

This is the single most important difference, and it is easy to miss because
both projects call the thing "egress".

OpenSandbox's egress is an enforcement point. A sandbox is created with a
`networkPolicy`, `defaultAction` defaults toward deny, and the sidecar drops
anything that does not match a rule — at the DNS layer, and at the packet layer
under `dns+nft`. A devbox cannot be configured to reach a host it was not
granted.

This repo's egress cannot deny anything. Its ruleset has `policy accept`
throughout; it counts bytes, shapes links, answers DNS and forwards. `HEADER_JOBS`
decides which hosts get a header, not which hosts are reachable. The stack
models egress *shaping and observability* — and
[`sandbox/README.md`](../sandbox/README.md) says so in as many words.

The consequence is worth stating plainly: **point this sandbox at an agent you
are not willing to watch, and it will happily let the agent reach the internet.**
The one default route that points at the egress buys you a place to observe and
meter the traffic, not containment.

### Shaping is the thing this repo has that OpenSandbox does not

Traffic shaping — `tbf` for rate, `netem` for delay and loss — appears nowhere
in OpenSandbox: not in its documented feature set, not in the egress policy
syntax, not in the egress guide. `RATE`, `DELAY`, `LOSS`, `BURST` and `LATENCY`
on both links, per controller, is a capability OpenSandbox does not offer.

Combined with the fact that `bin/sandbox rules <controller>` prints a complete
nftables ruleset with no container running, this repository is better than
OpenSandbox at one specific thing: **demonstrating and testing network behaviour
deterministically.** OpenSandbox is better at almost everything else.

### Ingress: L4 and transport-agnostic versus L7 and opinionated

|  | Worktainer's ingress | OpenSandbox's ingress |
| --- | --- | --- |
| Layer | L3/L4 — nftables DNAT on a published port | L7 — an HTTP/1.1 and WebSocket reverse proxy |
| Carries | any protocol: SSH, HTTP, VNC, raw TCP | HTTP and WebSocket only |
| Routing | static `FORWARDS` list in `compose.yaml`, rewritten to fixed IPs | `<sandbox-id>-<port>` in a header, or `/<sandbox-id>/<port>/…` in the path, or a signed route token |
| Terminates TLS | no (it never sees any) | no, explicitly — "the ingress speaks cleartext HTTP/1.1 and never terminates TLS" |
| Reply path | pinned by a postrouting masquerade | conntrack and the reverse proxy |
| WebSocket | works, because it is just a port | a first-class path: 64 MiB messages, subprotocols and close codes propagated verbatim, 45 s handshake budget |

The WebSocket row is OpenSandbox's doing and this repo gets it for free by not
being an L7 proxy at all. The TLS row is the cost of the same simplicity:
putting OpenSandbox's ingress in front of anything requires an L7 TLS
terminating proxy in front of it, and WebSocket-over-HTTP/2 must be specifically
avoided or the upgrade never reaches the handler.

Because Worktainer's ingress moves packets rather than requests, **`ssh -p 2222`
is the primary way into the devbox** and OpenSandbox has no equivalent. Its access
model is API keys, endpoint headers and signed route tokens — there is no SSH
path through the gateway.

### Credential injection: broader but shallower

|  | Worktainer (`auth_inject.py`) | OpenSandbox (Credential Vault) |
| --- | --- | --- |
| Match on | host, and anything under it (`api.example.com` also matches `eu.api.example.com`) | scheme, host, port, method and path (`/v1/*`) |
| Header form | free-form: the KV field names *are* the header names | typed `auth` rules: `bearer`, `basic`, `apiKey`, `customHeaders`, `passthrough` |
| Several headers at once | yes — several fields in one secret become several headers | `customHeaders`, each backed by its own credential |
| Beyond headers | no | scoped placeholder substitution in path, query, header and body |
| Guard rails | a malformed `HEADER_JOBS` line is dropped; a failed secret read keeps the previous headers | path-ambiguity guard (dot-segments and backslashes → `403`), active-vault socket that the workload cannot reach, `304`/ETag snapshot reuse, write-only plaintext |
| Where the secret lives | **an OpenBao container**, which also stores things that are not credentials | the sidecar's own memory, served over a Unix socket inside the sidecar |
| Rotation | up to `BAO_RESYNC` (default 300 s), a background thread, never on the request path | next flow after the store's ETag changes — no cache-TTL delay |
| Enforcement mode needed | none (interception is optional and off by default) | refuses to activate unless `[egress].mode = "dns+nft"`, because direct-IP dials would bypass DNS-only policy |

Read one way, this repo's model is **broader**: any header, any number of them,
a whole external vault that outlives the component reading it. Read the other
way, it is **shallower**: a credential bound to `api.example.com` goes on
*every* request to that host, including a path the credential was never meant
for. OpenSandbox forces you to scope by method and path and rejects the loose
cases. For an LLM provider key that is mostly fine; for anything with a
per-endpoint scope it is not.

There is also a small design difference worth naming. OpenSandbox keeps the
credential store inside the thing that uses it, so there is no second container
to reach. This repo puts OpenBao on the data network and gives it a second,
non-credential job — the devbox's `authorized_keys` — which OpenSandbox has no
use for. That is why the `authorized_keys` secret exists here and has no
counterpart there.

### Secrets management: a vault container versus a vault API

The credential-injection section above is about *what goes on the wire*. This
one is about *where secrets live and who may read them*, and the two projects
answer from opposite directions.

| | Worktainer (OpenBao) | OpenSandbox |
| --- | --- | --- |
| Model | **pull** — consumers read from a vault on a timer or at boot | **push** — the host-side SDK writes credentials into the sidecar |
| Where the store is | a container on the data network, `10.89.1.20:8200` | the egress sidecar's memory, served over a Unix socket inside the sidecar |
| What it serves | any secret — credentials *and* the devbox's `authorized_keys` | only credentials, and only for outbound request injection |
| Inbound access control | sshd public keys, read from the secret at boot | `SecureAccessToken` header, or a signed route token with `expires`; `401` on either failure |
| Control-plane auth | none — there is no API to authenticate to | `[server].api_key` / `OPENSANDBOX_SERVER_API_KEY`; leaving it unset demands an explicit `YES` risk acknowledgment at startup |
| Access control *inside* the store | none — one root token, no policies, no audit device, no seal | three vault-write guard switches: `REQUIRE_TLS` (TLS, loopback, or a trusted proxy's `X-Forwarded-Proto`), `TRUSTED_PROXY_CIDRS`, `REQUIRE_SCOPED_MATCH` |
| Transport to the consumer | plain HTTP over the data network | a Unix socket the workload cannot reach — no network hop to intercept |
| Durability | in memory (dev mode), so a restart wipes it | in memory; Kubernetes pause/resume loses it; the fast-sandbox profile adds one file per sandbox under a Pod `emptyDir` |
| Rotation | write the value, then trigger the consumer — `bin/sandbox exec devbox sshd-init`, or wait out `BAO_RESYNC` | re-`create`/`patch` the vault; the next flow sees the new `ETag` with no cache-TTL delay |
| Who can read everything | anyone with the repo — the root token is literally in `compose.yaml` | the host-side control plane; plaintext is write-only and never returned by `get`, `list` or `patch` |
| Non-credential secrets | yes, that is the point of it | no counterpart |

The shape of the trade: OpenSandbox's push model removes a network hop and a
container to attack, and it never writes a secret to disk in any deployment mode
that matters. It also means the control plane has to know, and re-push, after
anything that replaces the sidecar — the credential-vault guide is explicit that
a Kubernetes pause/resume starts with an empty vault and the host must recreate
the bindings before resuming credentialed work. This repo's pull model repairs
itself on a timer, and its failure direction is the safe one: no stored keys
means nobody can log in, and an emptied secret strips its headers rather than
leaving whatever the agent sent.

What this repo does not have is any of the store-side access control. The
OpenBao container is in dev mode — plain HTTP, one root token, no policies, no
audit device, no seal — and
[`sandbox/openbao/README.md`](../sandbox/openbao/README.md) says plainly that it
is not a vault for anything you care about. OpenSandbox's equivalents are off by
default and documented as deployment hardening, but they exist as switches
rather than as prose.

Two more OpenSandbox credential planes have no counterpart here at all:
**secure access** (signing keys in `[ingress.secure_access]`, or in
`OPENSANDBOX_SECURE_ACCESS_KEYS` to keep key material out of the config file,
with a documented rotation procedure — add a key, deploy, then flip `active_key`)
and **execd's access token** (`X-EXECD-ACCESS-TOKEN`). This repo's ingress is an
unauthenticated DNAT: anything that can reach a published port reaches whatever
is behind it. The devbox's own sshd is public-key-only with keys from the vault,
which covers the port that matters, but `:8080` and `:8200` are open to anything
that can reach the host.

### Observability: five counters versus a metrics programme

Both controllers in this repo run `otel-cli` and emit **one span per interval**
named `net.counters`, with nftables byte counters as attributes. `otel-cli` is a
traces-only tool with no metrics command, so the counters ride as span
attributes rather than as a metrics pipeline — a stated limitation, not an
oversight. The five counters are `forwarded`, `up`, `down`, `dns` and `proxied`.

The reason for three containers is also unlike anything in OpenSandbox: **the
same spans are fanned out to all three backends** (o11ylite, otel-desktop-viewer,
otelop) so the identical numbers can be compared through three different stores.
OpenSandbox exports to *one* configured endpoint per component.

Beyond the mechanism, OpenSandbox's telemetry is where its operational maturity
shows:

- **Cardinality is bounded by design.** No queried domain, destination, sandbox
  name or secret ever becomes a label.
- **Failure semantics are documented so they cannot be misread.** `denied` (the
  policy worked) and `failed` (the sidecar could not do its job) are separate
  counters, because alerting on the wrong one inverts the diagnosis. This repo
  has no equivalent distinction at all.
- **`system` versus `process` metrics are kept apart**, because inside a
  container `gopsutil` reports the *node*, so every sandbox would publish the
  same number under its own ID.
- **The OTLP endpoint is auto-allow-listed** under a default-deny policy, so the
  sidecar does not block its own telemetry.

None of that is here. What is here is an honest account of a limit plus a
side-by-side comparison harness, which is a different and smaller win.

### Configuration: one manifest plus compose environment versus a typed server config

Both projects treat configuration as a first-class artefact. They are solving
different problems with it, and the difference shows up in what each one can
refuse at load time.

This repo has two manifests and one environment:

- **`mise.toml`** at the repo root — `[tools]`, `[dotfiles]`, `[bootstrap.packages]`
  — plus `sandbox/dev/mise.toml`, the same thing minus the host-only packages and
  plus the devbox's sshd config. Both point at one folder, `dotfiles/`, so there
  is a single source for every config file the image, a fresh machine and the
  host all share.
- **`sandbox/compose.yaml`** — the whole topology, and effectively the sandbox's
  real configuration: three networks with their options, every static IP, the
  `FORWARDS` port map, `HEADER_JOBS`, the `BAO_*` and `OTEL_*` variables and the
  shaping knobs.
- **Two mini-languages embedded in environment variables** — `FORWARDS` is
  `host-port:target-ip:target-port` per line and `HEADER_JOBS` is
  `<host> bao:<mount>/<path>` per line. These are the closest thing either
  project has to a policy language, and both generate real infrastructure from
  them: a nftables ruleset and a mitmproxy addon.

OpenSandbox has one typed file and three planes:

- **`~/.sandbox.toml`**, with a Pydantic schema in `opensandbox_server/config.py`
  named as the source of truth, across roughly fifteen sections: `[server]`,
  `[proxy]`, `[log]`, `[runtime]`, `[docker]`, `[kubernetes]`,
  `[agent_sandbox]`, `[ingress]`, `[egress]`, `[storage]`, `[store]`,
  `[secure_runtime]`, `[renew_intent]`, `[automation]`, `[otel]`.
- **The create request** — `networkPolicy`, `resourceLimits`, `volumes`,
  `secureAccess`, `extensions`, `image`.
- **Runtime policy** — `GET /policy` to inspect the effective policy,
  `PATCH /policy` to mutate it while sandboxes are running.

Five contrasts are worth naming.

| | Worktainer | OpenSandbox |
| --- | --- | --- |
| Duplication of defaults | the same defaults appear in `entrypoint.sh` and `compose.yaml`; each README table says "defaults live in `entrypoint.sh` and mirror `compose.yaml`" | one schema is authoritative; the docs name it and rank it against the example TOMLs and the release notes |
| Refusing bad config | none — `podman-compose config`, `sh -n` and the nft render catch syntax, not intent | cross-field validation at load (Docker mode forbids `[kubernetes]` and `firecracker`, forces `ingress.mode = "direct"`; gateway mode requires `[ingress.gateway]`; `idle_pause` requires a Redis DSN), and startup validation refuses to launch on a missing secure runtime |
| Admin vs per-request config | one plane — everything is in `compose.yaml`, including which secret path to read | three planes, with sidecar variables rejected when they arrive in a request `env`, because they are admin-only |
| Where secrets live in config | the root token is in `compose.yaml`, deliberately | key material is pushed out to `OPENSANDBOX_SECURE_ACCESS_KEYS`, `OPENSANDBOX_SERVER_API_KEY`, `OPENSANDBOX_STORE_POSTGRESQL_DSN`, and the Helm chart's `existingSecret` |
| Inspecting effective config | `bin/sandbox rules <service>` renders the whole nftables ruleset with no container running; `bin/sandbox nft` shows the live one | `GET /policy` returns the effective policy; `bin/sandbox` has no declarative policy to inspect, only counters |

The `rules` subcommand is the property this repo has that OpenSandbox does not:
the entire network configuration can be rendered as text, diffed and validated
against a real kernel (`bin/sandbox rules egress | unshare -rn nft -c -f /dev/stdin`)
without a container, a network, or a running stack. OpenSandbox's equivalent is
a published Go image and a running sidecar.

There is also one whole axis this project has and OpenSandbox does not:
**workload configuration**. `dotfiles/` and mise deploy the actual configuration
of the tools an agent will use — shell, editor, terminal multiplexer, git
client, VCS — into a sandbox image, and the same sources feed a fresh machine
and the host. OpenSandbox's answer to "make the devbox look like my machine" is
"pass any `image` you like". That is a real and useful difference: it means the
sandbox here is a developer's environment, not just a process jail.

### The rest, briefly

| | Worktainer | OpenSandbox |
| --- | --- | --- |
| Policy language | none — no allow/deny exists | FQDN, wildcard, IP, CIDR, port-scoped rules; platform `deny.always`/`allow.always` overlays; a `reachable.ports.cap` floor |
| Limits | none — the devbox can use the whole machine | `resourceLimits` for CPU, memory, GPU |
| Lifecycle | `bin/sandbox up/down/clean` | create, list, renew, pause, resume, delete, with TTLs and renew-on-access |
| Snapshots | none | Docker image commit; `SandboxSnapshot` CR pushing to an OCI registry; rootfs pause/resume; Firecracker checkpoints |
| Density | one devbox | `Pool` for pre-warmed pods, `BatchSandbox` batch creation, FastPath allocation — built for eval and RL training |
| Exec API | ssh, or `podman exec` | `execd`: SSE command streaming, PTY over WebSocket, file and directory ops, Jupyter code contexts, `/metrics`, OOM-kill detection |
| Concurrency | one agent | shared egress process per Fastlet pod, one subject per sandbox |

The isolation row at the top is a nice illustration of the tension this repo
sidesteps. Under OpenSandbox, gVisor has no `nat` table, so the egress sidecar
cannot install its redirect rules; the server refuses the combination with a
`400`, and the docs steer you to Kata. This repo has no policy layer to be
incompatible with, which is a real simplicity advantage — and also the reason it
cannot enforce anything.

## Is this a substitute for OpenSandbox?

No, and the honest answer depends on the question:

- **"Run an agent safely, at scale, from software."** OpenSandbox wins outright.
  This repo has no API, no policy, no resource limits, no isolation beyond runc,
  and one hardcoded devbox IP.
- **"Understand and demonstrate what egress interception, credential brokering
  and traffic shaping actually do, and read every line involved."** This repo
  wins, and OpenSandbox is close to useless for it — the components are
  separate published images and the interesting parts are behind an API.
- **"Get a devbox that matches my dotfiles."** OpenSandbox takes an arbitrary
  `image`, so this repo's devbox image is a candidate — but not a drop-in. The
  three-network topology depends on podman options (`no_default_route`, `--route`,
  `metric`) and static addressing that OpenSandbox's egress sidecar model
  replaces by sharing its own network namespace. It would need rework, not a
  config change.

Running both side by side is the most useful arrangement if the goal is
learning: this repo's `bin/sandbox` as the readable implementation, OpenSandbox
as the one to check the design against.

## Worth taking from OpenSandbox

In rough order of value per unit of work:

1. **A deny-by-default policy in the egress.** This is the gap that matters.
   `HEADER_JOBS` already parses a per-host list and the ruleset is already
   generated from data in `compose.yaml`, so allow/deny rules and a
   `defaultAction` fit where the job list already sits. Without it the stack
   observes traffic; with it, it bounds it.
2. **Scoping credentials by method and path.** `HEADER_JOBS` should grow a
   methods-and-paths matcher rather than sending a host-scoped key on every
   request to that host.
3. **Bounded-cardinality telemetry, and the `denied` vs `failed` split.** The
   counters are already OTLP; what is missing is the discipline that makes them
   safe to alert on.
4. **`resourceLimits`.** The devbox is on a shared machine and can starve
   whatever else is running.
5. **A `denied` counter and a policy counter** so the ruleset's decisions become
   as observable as its traffic — `bin/sandbox check` currently proves the rules
   are installed, not that they fire.
6. **One authoritative config source.** Every default currently exists twice —
   once in `entrypoint.sh`, once in `compose.yaml` — and the two can drift
   silently. OpenSandbox names its schema as the source of truth and ranks it
   against the examples; this repo could name `compose.yaml` the same way and
   have the entrypoints read nothing but what they are given.
7. **Validation that refuses rather than warns.** Cross-field rules at load and
   a startup check that fails loudly beat `podman-compose config` passing on a
   typo that silently disables a forward.
8. **Key material out of the config file.** The OpenBao root token is in
   `compose.yaml` on purpose here, which is a defensible trade for a throwaway
   sandbox — but a `BAO_TOKEN` read from an env file or a podman secret would
   cost almost nothing and remove the one line that makes the repo equivalent to
   the vault.
9. **Signing and pinning the images.** Cosign keyless signing plus digest
   pinning is a small addition against a real supply-chain story.

Not worth copying: the API, SDK, CRD and platform surface. That is a product's
job, and a dotfiles-and-one-sandbox repository would be carrying a large amount
of code that nothing in it needs.

Worth keeping precisely as they are: traffic shaping (OpenSandbox has nothing
like it), an L4 ingress that carries SSH, the secrets container doing double duty
for `authorized_keys`, three telemetry backends fed the same spans for
comparison, `bin/sandbox rules` printing a real ruleset with no container
running, and one source of config (`dotfiles/`) shared by the image, a fresh
machine and the host.

## Caveats on this comparison

- **OpenSandbox moves fast** — it is Apache-2.0, CNCF-listed, actively pushed,
  and roughly 15.9k stars. Everything above is as of its `main` on 2026-10-18
  and may be stale by the time this is read. Its egress L7 configuration surface
  is marked experimental, and an internal OSEP-0023 credential-admission runtime
  is under development behind a default-off gate.
- **Only the documentation was read**, not the code. Implementation detail —
  which nftables calls a ruleset really makes, how the sidecars bind — is
  inferred from the project's own architecture, egress, vault, telemetry,
  ingress and secure-runtime guides.
- **"No policy in Worktainer is a finding, not a criticism.** It is a deliberate
  scope boundary, stated in [`sandbox/README.md`](../sandbox/README.md) §
  Caveats. The comparison is written to make the boundary concrete, not to argue
  it was drawn in the wrong place.
- **The worktree state matters for any claim about this repo.** The nftables
  rulesets, the mitmproxy addon, `sshd-init` and the CA have each been validated
  against the real component they talk to, on the host namespace rather than in
  the stack, because rootless podman does not work in the environment this was
  built in. `bin/sandbox up` and `bin/sandbox check` going green end to end are
  still unverified, and that status is tracked outside the repository.

## See also

- [Sandbox](./sandbox.md) — this repository's sandbox, from the outside.
- [`sandbox/README.md`](../sandbox/README.md) — topology, counters, runbook and
  caveats.
- [`sandbox/egress/README.md`](../sandbox/egress/README.md) — what the MITM costs
  and how auth injection is wired.
- [`sandbox/openbao/README.md`](../sandbox/openbao/README.md) — the secrets
  layout.
- [OpenSandbox architecture](https://github.com/opensandbox-group/OpenSandbox/blob/main/docs/architecture/index.md),
  [egress](https://github.com/opensandbox-group/OpenSandbox/blob/main/docs/architecture/network/egress.md),
  [credential vault](https://github.com/opensandbox-group/OpenSandbox/blob/main/docs/guides/credential-vault.md),
  [secure runtimes](https://github.com/opensandbox-group/OpenSandbox/blob/main/docs/guides/secure-container.md)