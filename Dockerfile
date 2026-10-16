# Development container for these dotfiles.
# Build: docker build -t dotfiles .
# Run: docker run -it dotfiles
FROM ubuntu:devel

# ca-certificates, curl: required to install mise
# git: not shipped by mise, needed by jj/git
# libatomic1: required by Node.js (installed via mise), missing on minimal Ubuntu
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
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

# Create the checkout as `dev` so it owns the working directory
RUN mkdir -p /home/dev/src/dotfiles
WORKDIR /home/dev/src/dotfiles
COPY --chown=dev:dev . .

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
