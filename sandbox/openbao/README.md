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
- **One root token, printed nowhere.** `BAO_DEV_ROOT_TOKEN_ID` pins it to
  `sandbox-root-token` (compose.yaml) so the clients and the docs can hardcode
  it; the upstream `-dev-no-store-token` keeps it out of the container's
  filesystem.
- **Plain HTTP, no seal, no policies, no audit device.** Nothing is encrypted
  at rest (there is no "at rest"), every request is a root token, and every
  write is logged nowhere. That is fine for a port published on loopback and a
  database that lives in memory; it is not a vault for anything you care about.

**The token is in compose.yaml**, so anything that can read the repo can read
and rewrite every secret. That is a deliberate trade: the sandbox models *egress
shaping*, not defense against you. Do not put a real credential in here — put a
credential scoped to a throwaway key, and rotate it like one.

## Secrets layout

KV v2 is mounted at `secret/` by default, so a secret's API path is
`secret/<path>` and its CLI name is `secret/<path>`:

| Path | Fields | Holds |
| ---- | ------ | ----- |
| `secret/devbox/authorized_keys` | `authorized_keys` | the whole `authorized_keys` file: one public key per line |
| `secret/egress/<provider>` | one field per header, the field name being the header (`x-api-key`, …) | outbound auth for the egress's proxy |

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

From inside the devbox the `bao` CLI is in the image already, and `BAO_ADDR`
/`BAO_TOKEN` are in its compose environment:

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
2. the address (`BAO_ADDR`) and root token (`BAO_TOKEN`) in that container's
   compose environment;
3. a read path. `depends_on: [openbao]` only orders startup; a consumer that
   starts early has to retry (as `sshd-init` and the egress proxy do).

### Changing the root token

Three places hold it, and they have to change together or the container comes up
with a token nobody has:

| Where | Key |
| ----- | --- |
| `compose.yaml`, `openbao` service | `BAO_DEV_ROOT_TOKEN_ID` |
| `compose.yaml`, `devbox` service | `BAO_TOKEN` |
| `compose.yaml`, `egress` service | `BAO_TOKEN` |

Then `bin/sandbox up`. The token is not what protects anything here — the file
is readable by anyone with the repo — it only stops anonymous writes.

### Moving the server

`10.89.1.20` appears in five places: the address table in
[`../README.md`](../README.md), the ingress `FORWARDS`/`ports`, and the
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