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

# Install mise to /root/.local/bin, the path hardcoded in the tracked bashrc
RUN curl https://mise.run | sh
ENV PATH="/root/.local/bin:${PATH}"

WORKDIR /root/src/dotfiles
COPY . .

# Same steps as docs/new-machine.md
RUN mise trust \
    && mise install \
    && mise dot apply

CMD ["/bin/bash"]
