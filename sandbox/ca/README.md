# sandbox/ca — the CA the sandbox signs with

`bin/sandbox ca` writes two files here:

| File | What it is |
| ---- | ---------- |
| `sandbox-ca.crt` | the root certificate; baked into the devbox image's trust store so the devbox trusts what the egress's proxy signs |
| `sandbox-ca.key` | the private key; used by the egress to sign the TLS it intercepts |

Both are generated per machine and **not committed** (see the repo's
`.gitignore`) — this README is the only tracked file in the folder, and it is
what makes the devbox's build context work before the CA exists.

Everything about *why* there is a CA here, and what it costs, is in
[`../egress/README.md`](../egress/README.md). In short: it is what makes
`https://` traffic from the devbox inspectable, and trusting it in the devbox
means trusting the sandbox's controllers with everything the devbox fetches.

Regenerate by deleting both files and running `bin/sandbox ca` again — which
means rebuilding the devbox (it has the old certificate baked in) and restarting
the egress (it caches the key it signs with).

## Changing it later

```sh
bin/sandbox ca                       # subject + fingerprint of the current one
openssl x509 -in sandbox/ca/sandbox-ca.crt -noout -text   # the whole certificate
```

To **rotate** (the devbox will refuse every intercepted `https` call until it is
rebuilt, so do it when nothing is running):

```sh
podman stop sandbox-devbox sandbox-egress    # or: bin/sandbox down
rm sandbox/ca/sandbox-ca.crt sandbox/ca/sandbox-ca.key
bin/sandbox ca
bin/sandbox build                           # bakes the new certificate in
bin/sandbox up
```

Keep the old pair around until the new one is deployed — anything still trusting
the old certificate (another image build, a host-level curl with
`--cacert`) breaks the moment it is gone.

To hand the CA to something outside the sandbox, copy `sandbox-ca.crt` (never
the `.key`): `curl --cacert sandbox/ca/sandbox-ca.crt https://…` shows what a
tool outside the devbox sees through the proxy.