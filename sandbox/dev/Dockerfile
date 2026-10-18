# Development container for these dotfiles.
#
# Build context: the repository root, so the image reads the real sources
# instead of a synced copy. Two things are copied in: the repo's `dotfiles/`
# folder (every config source) and `sandbox/dev/mise.toml`, this image's own
# config. Together they mirror the repo layout — `mise.toml` at the checkout
# root with the sources under `dotfiles/` — so the image ships nothing else
# (no docs/, no .git, no other sandbox services).
#
# Build (from the repo root):
#   podman build -f sandbox/dev/Dockerfile -t worktainer .
# or: bin/sandbox build            # sets the context for you
# Run:   podman run -it worktainer
FROM ubuntu:devel

# ca-certificates, curl: required to install mise
# git: not shipped by mise, needed by jj/git
# libatomic1: required by Node.js (installed via mise), missing on minimal Ubuntu
# openssh-server: the devbox's sshd (unprivileged; see the ssh step below)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    libatomic1 \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

# Unprivileged user. It owns the mise toolchain and the dotfiles checkout, but
# gets no sudo and no other way to escalate. Everything below runs as it.
RUN useradd --create-home --shell /bin/bash --uid 1000 dev
USER dev

# Install mise to ~/.local/bin, the per-user path the tracked bashrc looks for
ENV HOME="/home/dev"
ENV PATH="/home/dev/.local/bin:${PATH}"
RUN curl https://mise.run | sh

# Create the checkout as `dev` so it owns the working directory. The checkout
# mirrors the repo root: mise.toml (this image's config, from sandbox/dev/)
# plus the repo's dotfiles/ folder, so every [dotfiles] source resolves inside
# the checkout — the same commands as docs/new-machine.md, run unchanged.
RUN mkdir -p /home/dev/src/dotfiles
WORKDIR /home/dev/src/dotfiles
COPY --chown=dev:dev dotfiles/ ./dotfiles/
COPY --chown=dev:dev sandbox/dev/mise.toml ./mise.toml

# useradd copies /etc/skel into $HOME, including a regular ~/.bashrc that would
# block the symlink; drop it so the repo's bashrc takes over (same for any other
# skel file that collides with a [dotfiles] target).
RUN rm -f ~/.bashrc

# Same steps as docs/new-machine.md.
# bat needs its cache built once so the vendored Catppuccin Frappe theme is picked
# up; shims aren't on PATH in a non-interactive build step, hence `mise exec`.
# mise dot apply also deploys the sshd config (dotfiles/sshd/, listed in
# mise.toml), which creates ~/.ssh/sshd for the next step.
RUN mise trust \
    && mise install \
    && mise dot apply \
    && mise exec -- bat cache --build

COPY --chown=dev:dev --chmod=0755 sandbox/dev/sshd-init.sh /usr/local/bin/sshd-init

# The sshd itself, started by sandbox/compose.yaml through `sshd-init`. It
# runs as the unprivileged `dev` — it may not touch /etc/ssh or /run, cannot
# bind port 22 and may not use PAM — hence its config, host key and pid file
# under ~/.ssh, port 2222 (a port above 1024; the ingress DNATs the host's
# 2222 to it) and PasswordAuthentication no in the sshd config.
#
# Who can log in is NOT decided here: sshd-init loads ~/.ssh/authorized_keys
# from OpenBao (secret/devbox/authorized_keys in sandbox-openbao), so key
# management stays live: store keys in the secret, restart the devbox.
# Only the host key is baked — every rebuild gets a new one and clients with
# cached known_hosts entries will see the change.
RUN chmod 700 ~/.ssh \
    && mkdir -p -m 700 ~/.ssh/sshd \
    && ssh-keygen -q -t ed25519 -N '' -C "devbox host key" \
        -f ~/.ssh/sshd/ssh_host_ed25519_key

CMD ["/bin/bash"]
