# Telemetry backend: otel-desktop-viewer.
#
# Thin wrapper over the upstream image so the sandbox builds one image per
# backend from a file in its own folder. See README.md.
FROM ghcr.io/ctrlspice/otel-desktop-viewer:latest

# 4317 OTLP gRPC, 4318 OTLP HTTP, 8000 web UI + JSON-RPC.
EXPOSE 4317 4318 8000
