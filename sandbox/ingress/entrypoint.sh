#!/bin/sh
# Ingress controller entrypoint.
#
# The container is the only way into the sandbox from the host:
#
#   1. the host ports published in sandbox-ingress.container are terminated
#      here;
#   2. nftables DNATs each of them to its backend on the data or control
#      network (the devbox, or a telemetry web UI);
#   3. the devbox-facing link is shaped with tc (tbf + netem);
#   4. a counter of everything forwarded is exported as OTel spans.
#
# All of it is driven by environment variables (see
# sandbox/quadlet/environments/ingress.env for the values).
# Set DRY_RUN=1 to print the nftables ruleset it would install and exit —
# no side effects, so it can be run outside a container.
set -eu

# --------------------------------------------------------------------------
# Configuration (the defaults here mirror environments/ingress.env, which is
# what the container actually gets)
# --------------------------------------------------------------------------
: "${CTRL_IP:=10.89.0.3}"          # this container's control-plane address
: "${DATA_IP:=10.89.1.3}"          # this container's data-plane address
# host-port:target-ip:target-port. environments/ingress.env sets the same
# list explicitly so the port map is visible next to the published ports in
# sandbox-ingress.container.
# The devbox pair points at the sshd built into the image (port 2222 inside
# the devbox; an unprivileged sshd cannot bind 22); 8200 is OpenBao's API/UI.
FORWARDS_DEFAULT="2222:10.89.1.10:2222 8080:10.89.1.10:8080 8200:10.89.1.20:8200 9419:10.89.0.20:80 9420:10.89.0.21:8000 9421:10.89.0.22:4319"
: "${FORWARDS:=$FORWARDS_DEFAULT}"
: "${RATE:=100mbit}"               # shaping for the devbox-facing link
: "${DELAY:=0ms}"                  # netem delay added to it
: "${LOSS:=0%}"                    # netem loss added to it
: "${BURST:=64kbit}"               # tbf burst
: "${LATENCY:=400ms}"              # tbf latency
: "${METRICS_INTERVAL:=15}"        # seconds between counter spans
: "${OTEL_SERVICE_NAME:=sandbox-ingress}"
: "${OTEL_ENDPOINTS:=}"            # space-separated OTLP/HTTP traces URLs

log() { printf '%s ingress: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

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

if [ -n "${DRY_RUN:-}" ]; then
    CTRL_IF=${CTRL_IF:-eth0}
    DATA_IF=${DATA_IF:-eth1}
else
    [ -n "$CTRL_IF" ] || { log "no interface holds $CTRL_IP"; exit 1; }
    [ -n "$DATA_IF" ] || { log "no interface holds $DATA_IP"; exit 1; }
    log "ctrl=$CTRL_IF ($CTRL_IP) data=$DATA_IF ($DATA_IP)"
fi

# --------------------------------------------------------------------------
# 1. The ruleset.
#
#   * prerouting: one DNAT rule per entry in FORWARDS, matching on the port
#     the host published. The port is what we match on, so it does not matter
#     which of this container's addresses the host's port proxy targeted.
#   * forward: counts every packet through the controller.
#   * postrouting: masquerades everything to this container's own address.
#     Without it, a backend's reply would leave over the bridge toward the
#     proxy's source address and never come back through here — conntrack
#     would never undo the rewrite, and the proxy would see a reply from an
#     address it never connected to. Forcing every reply to be routed here
#     pins the return path to the controller.
# --------------------------------------------------------------------------
RULES=/tmp/ingress.nft
{
    echo 'table inet ingress {'
    echo '    counter forwarded {}'
    echo ''
    echo '    chain prerouting {'
    echo '        type nat hook prerouting priority dstnat; policy accept;'
    for fwd in $FORWARDS; do
        host_port=${fwd%%:*}
        rest=${fwd#*:}
        target_ip=${rest%%:*}
        target_port=${rest#*:}
        for proto in tcp udp; do
            # `dnat ip to`: an inet table holds both families, so nftables
            # wants the address family spelled out.
            printf '        %s dport %s counter dnat ip to %s:%s\n' \
                "$proto" "$host_port" "$target_ip" "$target_port"
        done
    done
    echo '    }'
    echo ''
    echo '    chain forward {'
    echo '        type filter hook forward priority filter; policy accept;'
    echo '        counter name forwarded'
    echo '    }'
    echo ''
    echo '    chain postrouting {'
    echo '        type nat hook postrouting priority srcnat; policy accept;'
    echo '        masquerade'
    echo '    }'
    echo '}'
} > "$RULES"

if [ -n "${DRY_RUN:-}" ]; then
    cat "$RULES"
    exit 0
fi

if [ -z "$FORWARDS" ]; then
    log "FORWARDS is empty: nothing will be forwarded"
fi

# --------------------------------------------------------------------------
# 2. Forwarding. Ingress forwards the DNAT'd connections to their backends, so
#    IP forwarding must be on and reverse-path filtering relaxed (a packet
#    arrives on one interface and leaves by another).
# --------------------------------------------------------------------------
sysctl_w net/ipv4/ip_forward 1
for f in all default "$CTRL_IF" "$DATA_IF"; do
    sysctl_w "net/ipv4/conf/$f/rp_filter" 0
    sysctl_w "net/ipv4/conf/$f/forwarding" 1
done

nft delete table inet ingress 2>/dev/null || true
nft -f "$RULES"
log "installed DNAT for: $FORWARDS"

# --------------------------------------------------------------------------
# 3. Shape the link towards the devbox (the download direction as seen from
#    the sandbox).
# --------------------------------------------------------------------------
shape "$DATA_IF" "$RATE" "devbox"

# --------------------------------------------------------------------------
# 4. Export counters as OTel spans, then stay in the foreground.
# --------------------------------------------------------------------------
OTEL_SERVICE_NAME="$OTEL_SERVICE_NAME" \
OTEL_ENDPOINTS="$OTEL_ENDPOINTS" \
METRICS_INTERVAL="$METRICS_INTERVAL" \
    /usr/local/bin/metrics.sh &
METRICS_PID=$!

log "ready (metrics every ${METRICS_INTERVAL}s)"
trap 'kill "$METRICS_PID" 2>/dev/null || true' TERM INT
wait "$METRICS_PID"
