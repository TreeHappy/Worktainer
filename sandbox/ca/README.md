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