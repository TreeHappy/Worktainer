# Egress controller: the only way out to the internet.
#
# Alpine + nftables (masquerade and the up/down/dns/proxied counters), iproute2
# (tc shaping), dnsmasq (the devbox's resolver) and otel-cli (exports the
# counters as OTel spans). python3 + mitmproxy add the auth-injecting TLS proxy:
# it decrypts the devbox's outbound https in order to set request headers, and
# takes the values from OpenBao. See README.md.
FROM alpine:3.21

ARG OTEL_CLI_VERSION=0.4.5
ARG MITMPROXY_VERSION=12.2.3

# mitmproxy is pinned because auth_inject.py speaks mitmproxy's addon API. Its
# compiled dependencies (cryptography, cffi, pydantic-core) publish musllinux
# wheels, so this needs no Rust or C toolchain; should a future release stop
# shipping them, add `build-base cargo openssl-dev` here and build from source.
RUN apk add --no-cache \
        ca-certificates \
        curl \
        dnsmasq \
        iproute2 \
        nftables \
        python3 \
        py3-pip \
    && pip3 install --no-cache-dir --break-system-packages \
        "mitmproxy==${MITMPROXY_VERSION}" \
    && mitmdump --version \
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

COPY dnsmasq.conf /etc/dnsmasq.conf
COPY entrypoint.sh metrics.sh /usr/local/bin/
COPY auth_inject.py /usr/local/bin/auth_inject.py
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/metrics.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
