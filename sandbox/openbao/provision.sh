#!/bin/sh
# OpenBao's boot sequence for the sandbox: run the dev server, then mint the two
# scoped tokens the devbox and the egress use.
#
# Why this exists (audit S1): with one root token in the stack, the devbox's
# environment held the token that could read every secret — including the LLM
# provider key the agent is not supposed to have — and write the devbox's own
# authorized_keys. An agent with code execution in the devbox could therefore
# take either. This script issues each client a token scoped to its own path, so
# a stolen one is worth exactly that one secret.
#
# Why it is a script rather than configuration: `server -dev` keeps storage,
# policies and tokens *in memory*. They are gone on every restart, so the
# policies have to be written and the tokens minted on every boot. There is no
# sealed storage file to ship.
#
# The tokens are written to a volume shared with the devbox and the egress, both
# of which mount it read-only. They never appear in a container's environment:
#
#   /vault/devbox.token   read   secret/data/devbox/authorized_keys
#   /vault/egress.token   read   secret/data/egress/*
#
# Nothing in either policy can write, list, or reach outside its own prefix.
# Verified against OpenBao 2.7.1 - see sandbox/README.md.
set -eu

BAO_DEV_ROOT_TOKEN_ID=${BAO_DEV_ROOT_TOKEN_ID:?must be set: it pins the dev root token}
VAULT_DIR=${VAULT_DIR:-/vault}
LISTEN=${BAO_DEV_LISTEN:-0.0.0.0:8200}
# The health and admin calls go over loopback at whatever port the server was
# told to bind, before anything is reachable from the network. Deriving it from
# LISTEN rather than repeating 8200 keeps the two in step.
HEALTH="http://127.0.0.1:${LISTEN##*:}"

log() { printf '%s openbao: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

# api METHOD PATH [BODY] — the root token, on the loopback side, before anything
# is reachable from the network.
api() {
    method=$1
    path=$2
    body=${3:-}
    if [ -n "$body" ]; then
        curl -sS -X "$method" "$HEALTH/v1/$path" \
            -H "X-Vault-Token: $BAO_DEV_ROOT_TOKEN_ID" \
            -H 'Content-Type: application/json' \
            -d "$body" -o /dev/null -w '%{http_code}'
    else
        curl -sS -X "$method" "$HEALTH/v1/$path" \
            -H "X-Vault-Token: $BAO_DEV_ROOT_TOKEN_ID" \
            -o /dev/null -w '%{http_code}'
    fi
}

# mint POLICY DISPLAY_NAME -> the client token on stdout
mint() {
    curl -sS -X POST "$HEALTH/v1/auth/token/create" \
        -H "X-Vault-Token: $BAO_DEV_ROOT_TOKEN_ID" \
        -H 'Content-Type: application/json' \
        -d "{\"policies\":[\"$1\"],\"display_name\":\"$2\",\"meta\":{\"consumer\":\"sandbox\"}}" \
        | sed -n 's/.*"client_token":"\([^"]*\)".*/\1/p'
}

# The dev server runs in the background so the policies can be written into it.
# `-dev-no-store-token` keeps the root token out of the container's filesystem;
# it is pinned anyway, because nothing else can bootstrap a token without it.
bao server -dev \
    -dev-root-token-id="$BAO_DEV_ROOT_TOKEN_ID" \
    -dev-no-store-token \
    -dev-listen-address="$LISTEN" &
server=$!

# Forward the signals systemd sends to us to the server, so `systemctl stop
# sandbox-openbao` actually stops it rather than orphaning it.
trap 'kill -TERM "$server" 2>/dev/null || true; wait "$server" 2>/dev/null || true; exit 0' \
    TERM INT

waited=0
# The first attempt will almost always fail: the listener is not up yet. Its
# complaint is the expected one, so it is not worth printing.
while [ "$(curl -sS -o /dev/null -w '%{http_code}' "$HEALTH/v1/sys/health" 2>/dev/null || echo 000)" != "200" ]; do
    kill -0 "$server" 2>/dev/null || { log "the server exited during boot"; exit 1; }
    waited=$((waited + 1))
    [ "$waited" -ge 100 ] && { log "the server never became healthy"; exit 1; }
    sleep 0.2
done
log "server up on $LISTEN"

# Two policies, one path each. `read` and nothing else: no write, no list, no
# cubbyhole, no token minting, no sys/*.
#
# These are the whole of S1's fix. Anything added to either is a new capability
# for whatever holds that token, so the paths stay exact rather than a prefix:
# the devbox gets one file, the egress gets the providers directory.
devbox_policy='path "secret/data/devbox/authorized_keys" {
  capabilities = ["read"]
}'
egress_policy='path "secret/data/egress/*" {
  capabilities = ["read"]
}'

# `api` takes JSON; the policies are HCL, so they go as a JSON string value.
# `jsonl` turns a multi-line policy into one line with \n escapes.
jsonl() {
    printf '%s\n' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n"$//'
}

[ "$(api PUT 'sys/policies/acl/devbox' "{\"policy\":\"$(jsonl "$devbox_policy")\"}")" = "204" ] \
    || { log "could not write the devbox policy"; exit 1; }
[ "$(api PUT 'sys/policies/acl/egress' "{\"policy\":\"$(jsonl "$egress_policy")\"}")" = "204" ] \
    || { log "could not write the egress policy"; exit 1; }
log "policies written: devbox, egress"

mkdir -p "$VAULT_DIR"

devbox_token=$(mint devbox sandbox-devbox)
[ -n "$devbox_token" ] || { log "could not mint the devbox token"; exit 1; }
egress_token=$(mint egress sandbox-egress)
[ -n "$egress_token" ] || { log "could not mint the egress token"; exit 1; }

# 0644: the devbox reads its own as uid 1000. The volume is root-owned and the
# clients mount it read-only, so a token cannot be replaced by whoever holds it.
printf '%s' "$devbox_token" >"$VAULT_DIR/devbox.token"
printf '%s' "$egress_token" >"$VAULT_DIR/egress.token"
chmod 0644 "$VAULT_DIR/devbox.token" "$VAULT_DIR/egress.token"
log "scoped tokens minted and written to $VAULT_DIR"

log "ready — the devbox and the egress hold their own token, not the root token"

wait "$server"