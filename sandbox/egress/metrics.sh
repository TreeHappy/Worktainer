#!/bin/sh
# Export the sandbox's nftables byte counters as OTel spans.
#
# The controllers do not run a metrics pipeline (otel-cli is a traces-only
# tool), so each scrape is emitted as one span named "net.counters" with the
# counter names as attributes. `bin/check` and the README explain what each
# counter means.
set -eu

: "${OTEL_SERVICE_NAME:=sandbox-egress}"
: "${OTEL_ENDPOINTS:=}"       # space-separated OTLP/HTTP traces URLs
: "${METRICS_INTERVAL:=15}"

# otel-cli defaults to gRPC; every endpoint in this topology speaks OTLP/HTTP.
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_SERVICE_NAME OTEL_EXPORTER_OTLP_PROTOCOL

log() { printf '%s metrics: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

# "name=bytes,name=bytes,..." from `nft list counters`, without jq.
counters() {
    nft list counters 2>/dev/null | awk '
        /counter [^ ]+ \{/ { name = $2; next }
        /bytes/            { printf "%s=%s ", name, $4 }
    '
}

# Fan a span out to every configured backend. A backend that is down must not
# kill the exporter, so failures are swallowed.
emit() {
    name=$1
    attrs=$2
    for endpoint in $OTEL_ENDPOINTS; do
        OTEL_EXPORTER_OTLP_TRACES_ENDPOINT="$endpoint" \
            timeout 5 otel-cli span \
                --service "$OTEL_SERVICE_NAME" \
                --name "$name" \
                --attrs "$attrs" \
            >/dev/null 2>&1 || true
    done
}

if [ -z "$OTEL_ENDPOINTS" ]; then
    log "OTEL_ENDPOINTS is empty: counters are only visible via nft"
fi

while :; do
    attrs=$(counters)
    if [ -n "$attrs" ]; then
        # Strip the trailing space and turn spaces into commas for --attrs.
        attrs=$(printf '%s' "$attrs" | tr ' ' ',')
        attrs=${attrs%,}
        emit "net.counters" "$attrs"
    fi
    sleep "$METRICS_INTERVAL"
done
