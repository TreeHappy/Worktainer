# Telemetry backend: O11yLite.
#
# The upstream image already contains the whole stack (OTLP receiver, DuckDB
# storage and the web UI); this Dockerfile exists so every backend is built
# from a file in its own folder, with its notes alongside. See README.md.
FROM ghcr.io/o11ylite/o11ylite:latest

# 80 serves both the web UI and the OTLP HTTP/gRPC ingress.
EXPOSE 80
