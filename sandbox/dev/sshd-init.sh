#!/bin/bash
# sshd-init: fill ~/.ssh/authorized_keys from OpenBao, for the sshd baked
# into the devbox image.
#
# The devbox sshd runs as the unprivileged `dev`, takes public keys only, and
# refuses root logins — so ALL SSH access is decided by the contents of
# ~/.ssh/authorized_keys. That file is not baked into the image: OpenBao
# serves it (secret/devbox/authorized_keys in sandbox-openbao, see
# sandbox/openbao/README.md), and this script pulls the current copy on every
# devbox boot. Changing the sandbox's keys is then an edit to the secret plus
# a devbox restart, not a rebuild.
#
# Environment (defaults mirror sandbox/quadlet/environments/devbox.env):
#   BAO_ADDR        http://10.89.1.20:8200    the OpenBao container
#   VAULT_DIR       /vault                    where this container's own token is
#   SSH_KEYS_PATH   secret/devbox/authorized_keys
#   SSH_KEYS_TRIES  10                        2 s apart, while openbao boots
#
# The token is read from $VAULT_DIR/devbox.token rather than taken from the
# environment, and it is *this container's* token: scoped to SSH_KEYS_PATH and
# nothing else. It is minted by sandbox/openbao/provision.sh at every boot,
# because dev-mode storage is in memory — so the first few attempts here are
# also waiting for the file to exist. The root token is not in this container
# at all (audit S1).
#
# Either way sshd still starts: with an empty key list nobody gets in (the
# failure is loud, and `bin/sandbox check` flags it), but the devbox itself
# stays usable through `bin/sandbox shell`.
set -u

BAO_ADDR="${BAO_ADDR:-http://10.89.1.20:8200}"
VAULT_DIR="${VAULT_DIR:-/vault}"
SSH_KEYS_PATH="${SSH_KEYS_PATH:-secret/devbox/authorized_keys}"
SSH_KEYS_TRIES="${SSH_KEYS_TRIES:-10}"

log() { printf '%s sshd-init: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

# The token this container is allowed to read one secret with. Empty means the
# vault has not finished booting, or has wiped (dev mode is in memory), and the
# retry loop below covers both.
vault_token() {
    [ -r "$VAULT_DIR/devbox.token" ] || return 1
    cat "$VAULT_DIR/devbox.token" 2>/dev/null
}

tries=$SSH_KEYS_TRIES
said_waiting=
while [ "$tries" -gt 0 ]; do
    if BAO_TOKEN=$(vault_token) && [ -n "$BAO_TOKEN" ] &&
        keys=$(BAO_TOKEN=$BAO_TOKEN bao kv get -field=authorized_keys "$SSH_KEYS_PATH" 2>/dev/null); then
        mkdir -p -m 700 ~/.ssh
        umask 077
        printf '%s\n' "$keys" > ~/.ssh/authorized_keys
        n=$(grep -c . ~/.ssh/authorized_keys || true)
        if [ "$n" -gt 0 ]; then
            log "authorized_keys: $n key(s) from $SSH_KEYS_PATH"
        else
            log "authorized_keys is empty in openbao — sshd accepts no logins until a public key is stored there"
        fi
        exit 0
    fi
    tries=$((tries - 1))
    if [ -z "$said_waiting" ]; then
        said_waiting=1
        log "no token in $VAULT_DIR/devbox.token yet, or $SSH_KEYS_PATH is not readable - retrying"
    fi
    sleep 2
done

log "giving up on $SSH_KEYS_PATH: sshd will accept no logins (bin/sandbox exec devbox sshd-init to retry)"
exit 0
