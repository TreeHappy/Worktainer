# Ingress controller: the only way in from the host.
#
# Alpine + nftables (port DNAT and the forwarded-packet counter), iproute2
# (tc shaping of the devbox-facing link) and otel-cli (exports the counters as
# OTel spans). See README.md for what it does and how to steer it.
FROM alpine:3.21

ARG OTEL_CLI_VERSION=0.4.5

RUN apk add --no-cache \
        ca-certificates \
        curl \
        iproute2 \
        nftables \
    && arch="$(uname -m)" \
    && case "$arch" in \
           x86_64)  arch=amd64 ;; \
           aarch64) arch=arm64 ;; \
       esac \
    && curl -fsSL -o /tmp/otel-cli.tgz \
        "https://github.com/equinix-labs/otel-cli/releases/download/v${OTEL_CLI_VERSION}/otel-cli_${OTEL_CLI_VERSION}_linux_${arch}.tar.gz" \
    && tar -xzf /tmp/otel-cli.tgz -C /usr/local/bin otel-cli \
    && rm -f /tmp/otel-cli.tgz \
    && otel-cli --version

COPY entrypoint.sh metrics.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/metrics.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
