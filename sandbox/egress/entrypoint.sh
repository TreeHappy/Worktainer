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
#   4. upload, download and DNS byte counters are exported as OTel spans.
#
# All of it is driven by environment variables (see compose.yaml for values).
# Set DRY_RUN=1 to print the nftables ruleset it would install and exit —
# no side effects, so it can be run outside a container.
set -eu

# --------------------------------------------------------------------------
# Configuration (defaults mirror compose.yaml)
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
#   * postrouting: rewrites the source to this container's WAN address, so the
#     reply comes back here and conntrack can route it on to the devbox.
# --------------------------------------------------------------------------
RULES=/tmp/egress.nft
{
    echo 'table inet egress {'
    echo '    counter up {}'
    echo '    counter down {}'
    echo '    counter dns {}'
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

nft delete table inet egress 2>/dev/null || true
nft -f "$RULES"
log "installed masquerade on $WAN_IF and up/down/dns counters"

# --------------------------------------------------------------------------
# 4. Shaping: the WAN link limits the upload, the data link limits what the
#    devbox can pull down.
# --------------------------------------------------------------------------
shape "$WAN_IF" "$UP_RATE" "wan (upload)"
shape "$DATA_IF" "$DOWN_RATE" "devbox (download)"

# --------------------------------------------------------------------------
# 5. Export counters as OTel spans, then stay in the foreground.
# --------------------------------------------------------------------------
OTEL_SERVICE_NAME="$OTEL_SERVICE_NAME" \
OTEL_ENDPOINTS="$OTEL_ENDPOINTS" \
METRICS_INTERVAL="$METRICS_INTERVAL" \
    /usr/local/bin/metrics.sh &
METRICS_PID=$!

log "ready (metrics every ${METRICS_INTERVAL}s)"
trap 'kill "$METRICS_PID" 2>/dev/null || true; kill "$(cat /run/dnsmasq.pid 2>/dev/null)" 2>/dev/null || true' TERM INT
wait "$METRICS_PID"
