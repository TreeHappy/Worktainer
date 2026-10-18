#!/bin/bash
# Container start sequence for the devbox: trust the sandbox CA, fetch the
# sshd's authorized keys from OpenBao, then hand the process over to sshd.
#
# Replaces the two-line `command:` that used to live in compose.yaml, which
# needed a script of its own as soon as the CA moved out of the image and into a
# bind mount (see below).
#
# The order matters and is the same as it has always been: no keys, no sshd
# problem, but sshd with an empty key list must still start so the devbox stays
# usable through `bin/sandbox shell`.
#
# The sandbox CA is bind-mounted read-only at /etc/sandbox/ca rather than baked
# into the image. Two reasons, and the second is the important one:
#
#   1. it is generated per machine (`bin/sandbox ca`) and gitignored, so the
#      flake that builds the image cannot see it at all;
#   2. naming sandbox/ca/ from nix would put the *private key* into the nix
#      store, which lands in the image — exactly the leak the old Dockerfile
#      had with `COPY sandbox/ca/ /tmp/sandbox-ca/` (audit S2). Mounting the
#      folder read-only keeps the key in the host's hands only.
#
# A consequence worth having: rotating the CA no longer needs an image rebuild,
# only a devbox restart.
#
# If no certificate is mounted the bundle is left alone. The devbox still boots;
# outbound https fails with certificate errors the moment the proxy is in the
# path, which `bin/sandbox check` reports.
set -u

CA_DIR=${CA_DIR:-/etc/sandbox/ca}
CA_CRT=$CA_DIR/sandbox-ca.crt
CA_BUNDLE=${CA_BUNDLE:-/etc/ssl/certs/ca-certificates.crt}

log() { printf '%s devbox: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

if [ -f "$CA_CRT" ]; then
    # Appending, not replacing: the bundle is the public roots, and this adds the
    # sandbox CA underneath them. The image's /etc is owned by dev (the whole
    # layer is), so this needs no root.
    if cat "$CA_CRT" >>"$CA_BUNDLE" 2>/dev/null; then
        log "trusting the sandbox CA from $CA_CRT"
    else
        log "cannot write $CA_BUNDLE — outbound https will fail once the proxy is in the path"
    fi
else
    log "no sandbox CA at $CA_CRT (run bin/sandbox ca) — interception will fail until there is one"
fi

command -v sshd-init >/dev/null 2>&1 && sshd-init

exec sshd -D -e -f ~/.ssh/sshd/sshd_config