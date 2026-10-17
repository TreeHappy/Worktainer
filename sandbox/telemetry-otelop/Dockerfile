# Telemetry backend: otelop.
#
# Thin wrapper over the upstream image so the sandbox builds one image per
# backend from a file in its own folder. See README.md.
FROM ghcr.io/mashiro/otelop:latest

# 4317 OTLP gRPC, 4318 OTLP HTTP, 4319 web UI + GraphQL.
EXPOSE 4317 4318 4319
