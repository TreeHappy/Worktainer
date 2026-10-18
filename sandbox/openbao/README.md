# OpenBao — the sandbox's secrets server

The devbox and the egress need credentials (an API key for the LLM provider an
agent talks to, the list of public keys allowed to log into the devbox). Those
must not live in the image, in the repo, or in the agent's environment, where a
prompt-injected agent could read them back out. So they live here: one
container, [OpenBao](https://openbao.org/), addressed over the data network at
`10.89.1.20:8200` and published to the host as `:8200` through the ingress.

What each consumer does with a secret:

| Consumer | Secret | On a change |
| -------- | ------ | ----------- |
| devbox sshd | `secret/devbox/authorized_keys` | `bin/sandbox exec devbox sshd-init`, or restart the devbox |
| egress proxy | `secret/egress/<provider>` | picked up by the egress's resync (`BAO_RESYNC`, default 5 min) |

## Dev mode, and what it costs

The container runs OpenBao's dev server (`server -dev`), which is what a
throwaway sandbox wants and what nothing else does:

- **Storage is in memory.** Every secret is gone after a restart. Re-store
  what you need, or keep your canonical copy of it (a `pass` file, a paper
  note) outside the sandbox. The devbox re-reads `authorized_keys` on its next
  boot, so a wiped server and a restarted devbox mean "no keys, nobody gets
  in" — the safe direction to fail in.
- **One root token, used only to bootstrap.** `BAO_DEV_ROOT_TOKEN_ID` pins it to
  `sandbox-root-token` ([`environments/openbao.env`](../quadlet/environments/openbao.env))
  so [`provision.sh`](./provision.sh) can use it at boot; the upstream
  `-dev-no-store-token` keeps it out of the container's filesystem. **Neither
  the devbox nor the egress ever sees it** — see below.
- **Plain HTTP, no seal, no audit device.** Nothing is encrypted at rest (there
  is no "at rest") and every write is logged nowhere. That is fine for a port
  published on loopback and a database that lives in memory; it is not a vault
  for anything you care about.

**Policies are scoped, even here.** In-memory storage means policies are gone on
every restart, so [`provision.sh`](./provision.sh) writes them at every boot. That
is not decoration: it is the fix for audit S1, where the root token sat in the
devbox's environment and the agent could read it — and with it the provider key
it was built not to have, and write its own SSH key.

## Scoped tokens (audit S1)

Each client gets a token that can read its own secret and nothing else. They are
minted on every boot and handed over through a shared volume, so neither token
is ever in a container's environment:

| Token | Path it may read | Held by |
| ----- | ---------------- | ------- |
| `/vault/devbox.token` | `secret/data/devbox/authorized_keys` | the devbox, read-only mount |
| `/vault/egress.token` | `secret/data/egress/*` | the egress, read-only mount |

Both policies are `capabilities = ["read"]` on those paths and nothing else —
no write, no list, no `sys/*`, no token minting. Verified against OpenBao 2.7.1
that each token is refused with 403 for everything outside its own path, and that
a devbox token cannot write `authorized_keys` even its own.

Consequences worth stating:

- `bin/sandbox exec devbox env | grep BAO_TOKEN` prints nothing.
- `bin/sandbox check` asserts all of this against the running stack, so S1
  cannot come back quietly.
- The root token is still in the repo, in `environments/openbao.env`. That is the
  remaining deliberate trade: anyone with the repo can read and rewrite every
  secret. It is not the same finding — S1 was about the *agent*, which does not
  have the repo. Do not put a real credential in here — put a credential scoped
  to a throwaway key, and rotate it like one.

## Secrets layout

KV v2 is mounted at `secret/` by default, so a secret's API path is
`secret/<path>` and its CLI name is `secret/<path>`:

| Path | Fields | Who may read it | Holds |
| ---- | ------ | --------------- | ----- |
| `secret/devbox/authorized_keys` | `authorized_keys` | the devbox's token | the whole `authorized_keys` file: one public key per line |
| `secret/egress/<provider>` | one field per header, the field name being the header (`x-api-key`, …) | the egress's token | outbound auth for the egress's proxy |

Anything you add here is unreachable: both policies are exact paths, so a new
secret needs a new policy in [`provision.sh`](./provision.sh) before either
client can see it. That is deliberate — a policy is a decision, and adding a
prefix to widen one is the kind of change that should be visible in a diff.

Both are plain KV: no policy, no lease, no rotation machinery — write the new
value, consumers pick it up.

## Recipes

Everything below talks to the host port, i.e. through the ingress. `jq` is used
to unwrap the KV v2 envelope (`.data.data.<field>`).

Store the devbox's authorized keys, from the host, no quoting games:

```sh
curl -sS -X POST http://127.0.0.1:8200/v1/secret/data/devbox/authorized_keys \
    -H 'X-Vault-Token: sandbox-root-token' \
    -d "{\"data\":{\"authorized_keys\":\"$(cat ~/.ssh/id_ed25519.pub)\"}}"
```

Several keys: repeat `authorized_keys` with a `\n` between them, or use the CLI
below, which reads the file verbatim.

From inside the devbox the `bao` CLI is in the image already, and `BAO_ADDR` is
in its environment. `BAO_TOKEN` is **not** — the devbox's token is scoped to
`secret/devbox/authorized_keys`, so use it explicitly:

```sh
bin/sandbox shell devbox
export BAO_TOKEN=$(cat /vault/devbox.token)
```

With that token you can read that one path and nothing else — `bao kv list
secret/` and `bao kv get secret/egress/anthropic` are both 403. Storing keys
needs the root token from the host, which the recipes above use:

```sh
bin/sandbox shell devbox
bao status                                   # server reachable, unsealed
bao kv put secret/devbox/authorized_keys \
    authorized_keys=@"$HOME/.ssh/id_ed25519.pub"
bao kv get -field=authorized_keys secret/devbox/authorized_keys
bao kv list secret/
bao kv delete secret/devbox/authorized_keys
```

…or use the web UI at <http://127.0.0.1:8200/ui> with the root token.

Health, for scripts and for `bin/sandbox check` — no token needed, and `200`
means active and unsealed:

```sh
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8200/v1/sys/health
```

## Rotating

1. Write the new value (a `kv put` replaces the whole secret).
2. Make the consumer re-read it: `bin/sandbox exec devbox sshd-init`, or wait
   out the egress's `BAO_RESYNC`.

There is no grace period between "new key stored" and "new key in force" for
the devbox — after `sshd-init`, exactly the stored list can log in. Keep your
current key in the list while you add the new one, in one secret:

```sh
bao kv get -field=authorized_keys secret/devbox/authorized_keys \
    > ~/.ssh/devbox_authorized_keys
$EDITOR ~/.ssh/devbox_authorized_keys     # add the new key, keep the old ones
bao kv put secret/devbox/authorized_keys \
    authorized_keys=@~/.ssh/devbox_authorized_keys
bin/sandbox exec devbox sshd-init
```

Pull the value out to edit it rather than appending to it with `cat`:
`bao kv get -field` does not promise a trailing newline, so two `cat`s glued
together can end up with two keys on one line, which sshd then rejects. Going
through an editor sidesteps that, and duplicate lines are harmless anyway.

Wiping the server is just a restart; re-seeding is the recipe above:

```sh
podman restart sandbox-openbao
```

## Configuring it later

### Adding a consumer

The pattern is the same whatever reads the secret: **address it by URL from the
container that needs it, read it at boot or on a timer, and never write it
anywhere the agent can reach.** Concretely, a new consumer is

1. a secret path (`secret/<service>/<thing>`), shaped for whoever reads it —
   field names as header names for the egress proxy, one whole-file field for
   the devbox's `authorized_keys`;
2. a policy in [`provision.sh`](./provision.sh) for exactly that path, and a
   token minted from it into `/vault/<consumer>.token`;
3. a read path, and the consumer reading its own token file rather than an
   environment variable. `Requires=` on the openbao unit orders startup but does
   not wait for the token to exist, so a consumer that starts early has to retry
   — as `sshd-init` and the egress proxy both do.

### Changing the root token

One place holds it now, which is the improvement:

| Where | Key |
| ----- | --- |
| `environments/openbao.env` | `BAO_DEV_ROOT_TOKEN_ID` |

Then `bin/sandbox up`. `provision.sh` mints fresh scoped tokens from it on every
boot, so there is nothing else to keep in step.

The root token is not what protects anything here — the file is readable by
anyone with the repo. It stops anonymous writes; scoping is what stops the
agent.

### Moving the server

`10.89.1.20` appears in five places: the address table in
[`../README.md`](../README.md), the ingress `FORWARDS`/`PublishPort=`, and the
`BAO_ADDR` of the devbox and the egress (plus the default baked into
`../dev/sshd-init.sh`). Change all of them; `bin/sandbox check` will tell you
if you missed one.

### Making secrets survive a restart

Not supported as configured, and deliberately so: dev mode keeps everything in
memory. Keep the canonical copy of a secret outside the sandbox and re-`kv put`
it after a restart — that is what the recipes above are for. If you need
persistence, this container has to stop being a dev server (a file or Consul
backend, `BAO_DEV_ROOT_TOKEN_ID` gone, real policies), which is a different
container and a different threat model.

### Looking around

```sh
bao kv list secret/                       # what exists
bao kv get secret/devbox/authorized_keys  # one entry (mind the trailing newline)
curl -s http://127.0.0.1:8200/v1/sys/health | jq   # 200 = active
```

The web UI at <http://127.0.0.1:8200/ui> shows the same thing with click-through.