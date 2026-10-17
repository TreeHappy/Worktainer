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
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    libatomic1 \
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
RUN mise trust \
    && mise install \
    && mise dot apply \
    && mise exec -- bat cache --build

CMD ["/bin/bash"]
