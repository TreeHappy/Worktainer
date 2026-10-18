#!/bin/sh
# Egress controller entrypoint.
#
# The container is the only way out of the sandbox:
#
#   1. it is the devbox's default gateway (the data network's route points at
#      its data address) and masquerades everything it forwards to the WAN;
#   2. it answers the devbox's DNS queries with dnsmasq, so name resolution
#      crosses the egress boundary too;
#   3. both the data-facing and WAN-facing links are shaped with tc;
#   4. it decrypts the devbox's outbound https (it has to, to set auth headers)
#      and injects values from OpenBao — see README.md;
#   5. upload, download, DNS and proxied byte counters are exported as OTel
#      spans.
#
# All of it is driven by environment variables (see
# sandbox/quadlet/environments/egress.env for the values).
# Set DRY_RUN=1 to print the nftables ruleset it would install and exit —
# no side effects, so it can be run outside a container.
set -eu

# --------------------------------------------------------------------------
# Configuration (the defaults here mirror environments/egress.env, which is
# what the container actually gets)
# --------------------------------------------------------------------------
: "${CTRL_IP:=10.89.0.2}"          # control-plane address
: "${DATA_IP:=10.89.1.2}"          # data-plane address (the devbox's gateway)
: "${WAN_IP:=10.89.2.2}"           # WAN address
: "${WAN_GW:=10.89.2.1}"           # WAN gateway, used only if the default is missing
: "${UP_RATE:=100mbit}"            # shaping for the WAN-facing link (upload)
: "${DOWN_RATE:=100mbit}"          # shaping for the data-facing link (download)
: "${DELAY:=0ms}"                  # netem delay
: "${LOSS:=0%}"                    # netem loss
: "${BURST:=64kbit}"               # tbf burst
: "${LATENCY:=400ms}"              # tbf latency
: "${DNS_UPSTREAM:=9.9.9.9}"       # resolver dnsmasq forwards to
: "${METRICS_INTERVAL:=15}"        # seconds between counter spans
: "${OTEL_SERVICE_NAME:=sandbox-egress}"
: "${OTEL_ENDPOINTS:=}"            # space-separated OTLP/HTTP traces URLs

# Auth-injecting TLS proxy (see README.md). Only armed when HEADER_JOBS names
# at least one secret: without it the devbox's https goes straight out.
: "${HEADER_JOBS:=}"               # "<host> bao:<mount>/<path>" per line
: "${PROXY_PORT:=8080}"            # mitmdump's listen port, and the redirect target
: "${PROXY_CONF_DIR:=/var/lib/mitmproxy}"   # where mitmproxy keeps its CA
: "${CA_DIR:=/etc/sandbox/ca}"     # the sandbox CA, bind-mounted read-only
: "${DEVBOX_IP:=10.89.1.10}"       # whose outbound 443 is intercepted
: "${SANDBOX_NETS:=10.89.0.0/16}"  # sandbox-internal space: never intercepted
: "${BAO_ADDR:=http://10.89.1.20:8200}"
: "${VAULT_DIR:=/vault}"           # where this controller's own token is
: "${BAO_RESYNC:=300}"             # seconds between secret re-reads; 0 = once
: "${MITM_VERBOSITY:=info}"         # mitmdump log level; warn hides per-request lines

if [ -n "$HEADER_JOBS" ]; then
    PROXY_ARMED=1
else
    PROXY_ARMED=0
fi

log() { printf '%s egress: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

# Print the interface that holds the given IPv4 address. Interfaces are found
# by address, not by name: podman does not promise an order when a container
# joins several networks.
iface_of() {
    ip -o -4 addr show 2>/dev/null \
        | awk -v ip="$1" '{ split($4, a, "/"); if (a[1] == ip) { print $2; exit } }'
}

# Best-effort write to a /proc/sys knob (the file may not exist in every
# kernel, and losing one rp_filter toggle should not abort the container).
sysctl_w() {
    if [ -w "/proc/sys/$1" ]; then
        printf '%s' "$2" > "/proc/sys/$1" 2>/dev/null || true
    fi
}

# Is anything listening on the proxy port? The local address column ends with
# ":PORT", which is more reliable to match than a substring of the whole line.
proxy_listening() {
    ss -ltn 2>/dev/null | awk 'NR > 1 { print $4 }' | grep -q ":$PROXY_PORT\$"
}

# tc shaping: tbf caps the rate, netem adds delay/loss when configured.
shape() {
    iface=$1
    rate=$2
    label=$3

    [ -n "$rate" ] || { log "no rate for $label, skipping shaping"; return 0; }
    tc qdisc del dev "$iface" root 2>/dev/null || true

    if ! tc qdisc add dev "$iface" root handle 1: tbf \
            rate "$rate" burst "$BURST" latency "$LATENCY" 2>/dev/null; then
        log "tbf failed on $iface (continuing unshaped)"
        return 0
    fi
    if [ "$DELAY" != "0ms" ] || [ "$LOSS" != "0%" ]; then
        tc qdisc add dev "$iface" parent 1:1 handle 10: netem \
            delay "$DELAY" loss "$LOSS" 2>/dev/null \
            || log "netem failed on $iface (rate is still shaped)"
    fi
    log "shaped $label ($iface): rate=$rate delay=$DELAY loss=$LOSS"
}

# --------------------------------------------------------------------------
# 0. Locate the interfaces by address.
# --------------------------------------------------------------------------
CTRL_IF=$(iface_of "$CTRL_IP")
DATA_IF=$(iface_of "$DATA_IP")
WAN_IF=$(iface_of "$WAN_IP")

if [ -n "${DRY_RUN:-}" ]; then
    CTRL_IF=${CTRL_IF:-eth0}
    DATA_IF=${DATA_IF:-eth1}
    WAN_IF=${WAN_IF:-eth2}
else
    [ -n "$CTRL_IF" ] || { log "no interface holds $CTRL_IP"; exit 1; }
    [ -n "$DATA_IF" ] || { log "no interface holds $DATA_IP"; exit 1; }
    [ -n "$WAN_IF" ] || { log "no interface holds $WAN_IP"; exit 1; }
    log "ctrl=$CTRL_IF data=$DATA_IF wan=$WAN_IF"
fi

# --------------------------------------------------------------------------
# 1. The ruleset.
#
#   * dns_queries: counts the devbox's lookups, which arrive as traffic
#     addressed to this container rather than through it;
#   * forward: `up` is what enters from the data link, `down` what leaves for
#     it;
#   * prerouting: hands the devbox's outbound https to the local proxy. It
#     counts there (`proxied`), so it sees requests only, not replies — the
#     reply bytes are counted by `down` on the way back;
#   * postrouting: rewrites the source to this container's WAN address, so the
#     reply comes back here and conntrack can route it on to the devbox.
# --------------------------------------------------------------------------
RULES=/tmp/egress.nft
{
    echo 'table inet egress {'
    echo '    counter up {}'
    echo '    counter down {}'
    echo '    counter dns {}'
    if [ "$PROXY_ARMED" -eq 1 ]; then
        echo '    counter proxied {}'
    fi
    echo ''
    echo '    chain dns_queries {'
    echo '        type filter hook input priority filter; policy accept;'
    printf '        iifname "%s" udp dport 53 counter name dns\n' "$DATA_IF"
    printf '        iifname "%s" tcp dport 53 counter name dns\n' "$DATA_IF"
    echo '    }'
    echo ''
    echo '    chain forward {'
    echo '        type filter hook forward priority filter; policy accept;'
    printf '        iifname "%s" counter name up\n' "$DATA_IF"
    printf '        oifname "%s" counter name down\n' "$DATA_IF"
    echo '    }'
    if [ "$PROXY_ARMED" -eq 1 ]; then
        echo ''
        echo '    chain prerouting {'
        echo '        type nat hook prerouting priority dstnat; policy accept;'
        printf '        ip saddr %s ip daddr != %s tcp dport 443 counter name proxied redirect to :%s\n' \
            "$DEVBOX_IP" "$SANDBOX_NETS" "$PROXY_PORT"
        echo '    }'
    fi
    echo ''
    echo '    chain postrouting {'
    echo '        type nat hook postrouting priority srcnat; policy accept;'
    printf '        oifname "%s" masquerade\n' "$WAN_IF"
    echo '    }'
    echo '}'
} > "$RULES"

if [ -n "${DRY_RUN:-}" ]; then
    cat "$RULES"
    exit 0
fi

# --------------------------------------------------------------------------
# 2. Forwarding and the default route.
#
# The data network adds `default via <DATA_IP>` to every member, and this
# container holds DATA_IP, so that route points at itself. Delete it and let
# the WAN default (metric 100) win.
# --------------------------------------------------------------------------
sysctl_w net/ipv4/ip_forward 1
for f in all default "$CTRL_IF" "$DATA_IF" "$WAN_IF"; do
    sysctl_w "net/ipv4/conf/$f/rp_filter" 0
    sysctl_w "net/ipv4/conf/$f/forwarding" 1
done

if ip route del default via "$DATA_IP" 2>/dev/null; then
    log "removed the self-referential default route via $DATA_IP"
fi
if ! ip route show default | grep -q .; then
    log "no default route; adding one via $WAN_GW dev $WAN_IF"
    ip route add default via "$WAN_GW" dev "$WAN_IF" metric 100
fi
log "default route: $(ip route show default | tr '\n' ' ')"

# --------------------------------------------------------------------------
# 3. DNS. dnsmasq listens on the data interface only and forwards upstream.
# --------------------------------------------------------------------------
dnsmasq --conf-file=/etc/dnsmasq.conf \
        --interface="$DATA_IF" \
        --server="$DNS_UPSTREAM" \
        --pid-file=/run/dnsmasq.pid
log "dnsmasq on $DATA_IF forwarding to $DNS_UPSTREAM"

# --------------------------------------------------------------------------
# 4. The auth-injecting TLS proxy, started before the redirect goes in — a
#    request in the window between the rule and the listener would be sent to a
#    closed port.
# --------------------------------------------------------------------------
#    Its token comes out of the shared vault volume rather than the
#    environment: the root token used to be in this container's environment
#    (audit S1), and what is in the volume instead is scoped to
#    secret/egress/* — the provider keys and nothing else, so it cannot reach
#    the devbox's authorized_keys or mint a token of its own.
PROXY_PID=
if [ "$PROXY_ARMED" -eq 1 ]; then
    if [ ! -r "$VAULT_DIR/egress.token" ]; then
        log "no token at $VAULT_DIR/egress.token - check bin/sandbox logs openbao; without it the proxy can read no header"
        exit 1
    fi
    BAO_TOKEN=$(cat "$VAULT_DIR/egress.token")

    # mitmproxy keeps its CA in <confdir>/mitmproxy-ca.pem as key+certificate
    # (and the bare certificate in mitmproxy-ca-cert.pem). Stage the sandbox
    # pair there, so the devbox only ever has to trust the sandbox CA.
    mkdir -p "$PROXY_CONF_DIR"
    if [ -f "$CA_DIR/sandbox-ca.key" ] && [ -f "$CA_DIR/sandbox-ca.crt" ]; then
        cat "$CA_DIR/sandbox-ca.key" "$CA_DIR/sandbox-ca.crt" \
            > "$PROXY_CONF_DIR/mitmproxy-ca.pem"
        cp "$CA_DIR/sandbox-ca.crt" "$PROXY_CONF_DIR/mitmproxy-ca-cert.pem"
        chmod 600 "$PROXY_CONF_DIR/mitmproxy-ca.pem"
        log "staged the sandbox CA from $CA_DIR into $PROXY_CONF_DIR"
    else
        log "no CA in $CA_DIR (run bin/sandbox ca): mitmproxy will mint its own, which the devbox does not trust"
    fi

    # Header values are read from OpenBao by the addon itself, on a timer —
    # never on the request path. MITM_VERBOSITY=warn silences mitmdump's
    # per-request lines (and the addon's secret reads with them).
    BAO_ADDR="$BAO_ADDR" \
    BAO_TOKEN="$BAO_TOKEN" \
    HEADER_JOBS="$HEADER_JOBS" \
    BAO_RESYNC="$BAO_RESYNC" \
        mitmdump \
            --listen-host 0.0.0.0 \
            --listen-port "$PROXY_PORT" \
            --set confdir="$PROXY_CONF_DIR" \
            --set termlog_verbosity="$MITM_VERBOSITY" \
            -s /usr/local/bin/auth_inject.py &
    PROXY_PID=$!

    waited=0
    while ! proxy_listening; do
        kill -0 "$PROXY_PID" 2>/dev/null || break
        waited=$((waited + 1))
        [ "$waited" -ge 50 ] && break
        sleep 0.2
    done
    if proxy_listening; then
        log "auth proxy on :$PROXY_PORT (headers from $BAO_ADDR, resync ${BAO_RESYNC}s)"
    else
        log "the auth proxy never listened on :$PROXY_PORT; the devbox's https will fail until it does"
    fi
else
    log "HEADER_JOBS is empty: outbound https from the devbox is not intercepted"
fi

nft delete table inet egress 2>/dev/null || true
nft -f "$RULES"
log "installed masquerade on $WAN_IF and up/down/dns counters$([ "$PROXY_ARMED" -eq 1 ] && printf ' plus the proxied redirect')"

# --------------------------------------------------------------------------
# 5. Shaping: the WAN link limits the upload, the data link limits what the
#    devbox can pull down.
# --------------------------------------------------------------------------
shape "$WAN_IF" "$UP_RATE" "wan (upload)"
shape "$DATA_IF" "$DOWN_RATE" "devbox (download)"

# --------------------------------------------------------------------------
# 6. Export counters as OTel spans, then stay in the foreground.
# --------------------------------------------------------------------------
OTEL_SERVICE_NAME="$OTEL_SERVICE_NAME" \
OTEL_ENDPOINTS="$OTEL_ENDPOINTS" \
METRICS_INTERVAL="$METRICS_INTERVAL" \
    /usr/local/bin/metrics.sh &
METRICS_PID=$!

cleanup() {
    kill "$METRICS_PID" 2>/dev/null || true
    if [ -n "$PROXY_PID" ]; then
        kill "$PROXY_PID" 2>/dev/null || true
    fi
    kill "$(cat /run/dnsmasq.pid 2>/dev/null)" 2>/dev/null || true
}

log "ready (metrics every ${METRICS_INTERVAL}s)"
trap 'cleanup; exit 0' TERM INT

# A dead proxy is silent from out here — every devbox https request would just
# fail to reach a closed port — so watch for it and let the restart policy
# bring the whole egress back rather than leaving the devbox offline.
while :; do
    if [ -n "$PROXY_PID" ] && ! kill -0 "$PROXY_PID" 2>/dev/null; then
        log "the auth proxy died; exiting so the container restarts with it"
        exit 1
    fi
    sleep 5
done
