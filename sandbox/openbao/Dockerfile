# Secrets server: OpenBao, in dev mode.
#
# Thin wrapper over the upstream image so the sandbox builds one image per
# container from a file in its own folder, with its notes alongside (the
# telemetry backends do the same). Everything that shapes how this runs lives
# in compose.yaml: the fixed dev-mode root token
# (BAO_DEV_ROOT_TOKEN_ID) and, on the clients, the address they read it at
# (BAO_ADDR). See README.md for the secrets layout and recipes.
FROM docker.io/openbao/openbao:latest

# 8200 serves both the API (v1/…) and the web UI (/ui). The upstream image
# already runs as the unprivileged `openbao` user and starts in dev mode
# (`server -dev -dev-no-store-token`), which keeps its storage in memory.
EXPOSE 8200