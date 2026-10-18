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
# Environment (defaults mirror compose.yaml):
#   BAO_ADDR        http://10.89.1.20:8200    the OpenBao container
#   BAO_TOKEN       sandbox-root-token        dev-mode root token
#   SSH_KEYS_PATH   secret/devbox/authorized_keys
#   SSH_KEYS_TRIES  10                        2 s apart, while openbao boots
#
# Either way sshd still starts: with an empty key list nobody gets in (the
# failure is loud, and `bin/sandbox check` flags it), but the devbox itself
# stays usable through `bin/sandbox shell`.
set -u

BAO_ADDR="${BAO_ADDR:-http://10.89.1.20:8200}"
BAO_TOKEN="${BAO_TOKEN:-sandbox-root-token}"
SSH_KEYS_PATH="${SSH_KEYS_PATH:-secret/devbox/authorized_keys}"
SSH_KEYS_TRIES="${SSH_KEYS_TRIES:-10}"

log() { printf '%s sshd-init: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

tries=$SSH_KEYS_TRIES
while [ "$tries" -gt 0 ]; do
    if keys=$(bao kv get -field=authorized_keys "$SSH_KEYS_PATH" 2>/dev/null); then
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
    log "cannot read $SSH_KEYS_PATH yet, retrying ($tries tries left)"
    sleep 2
done

log "giving up on $SSH_KEYS_PATH: sshd will accept no logins (bin/sandbox exec devbox sshd-init to retry)"
exit 0
