# Image builders for the three images this repo owns.
#
# The output of every builder here is a docker-format tarball, which is what
# `podman load` takes:
#
#   nix build ./nix#sandbox-ingress && podman load < result
#
# Two things about nix images shape this file.
#
# ## Store paths stay store paths
#
# A `contents` entry lands in the image at its own store path, so a script
# built into `pkgs.runCommand` ends up at `/nix/store/<hash>-ingress-bin/bin/
# entrypoint.sh` — not at `/usr/local/bin/entrypoint.sh`, where the entrypoints
# and `bin/check` expect it. Anything that needs an absolute path outside /nix
# is placed with `extraCommands`, which runs inside the layer directory with the
# layer as the working directory.
#
# ## Every file is owned by root
#
# `buildLayeredImage` copies each content with `rsync --chown=0:0` and tars
# with `--owner=0 --group=0`, so a uid-1000-owned `/home/dev` is not something it
# can express. `userImage` below is the way around that, and only the devbox
# needs it: sshd refuses to start unless the account and its ~/.ssh are owned
# by that account.
{ pkgs, lib }:
rec {
  # `/bin/sh` for the entrypoints, which are `#!/bin/sh` and POSIX throughout.
  #
  # A nix closure has no `/bin` at all; bash is at its store path. Without this
  # shim the container has nothing to execute and fails before the first line of
  # the entrypoint runs.
  sh = pkgs.runCommand "sandbox-sh" { } ''
    mkdir -p $out/bin
    ln -s ${pkgs.bashInteractive}/bin/bash $out/bin/sh
  '';

  # Everything in the closure, merged into one tree, plus the shim.
  rootClosure = paths: pkgs.symlinkJoin {
    name = "sandbox-root";
    paths = paths ++ [ sh ];
  };

  # A root-owned image: the common case, and what both controllers want — they
  # need NET_ADMIN and install nftables rules.
  #
  #   name          the repository tag, e.g. "localhost/sandbox-egress"
  #   contents      store paths merged into /, at their store locations
  #   extraCommands shell run inside the layer, for files that need a real path
  #   entrypoint    the argv the container runs
  #   cmd           arguments for the entrypoint
  #   env           KEY=VALUE strings
  #   user          the default user ("0" is root)
  #   uid gid       who owns every file in the image (0 is root)
  #
  # `uid`/`gid` apply to the *whole* layer, not a subtree — the layer is tarred
  # with `--owner`/`--group`. That is what lets the devbox be a uid-1000 user
  # that owns its own home, which sshd insists on. It also means /nix and /etc
  # belong to `dev` there, which is untidy and harmless: nothing in that image
  # runs as root.
  layeredImage =
    {
      name,
      contents,
      extraCommands ? "",
      entrypoint,
      cmd ? [ ],
      env ? [ ],
      user ? "0",
      uid ? 0,
      gid ? 0,
    }:
    pkgs.dockerTools.buildLayeredImage {
      inherit name contents extraCommands uid gid;
      config = {
        Entrypoint = entrypoint;
        Cmd = cmd;
        Env = env;
        WorkingDir = "/";
        User = user;
      };
    };

  # An image with a non-root account that owns a directory tree.
  #
  #   name       the repository tag
  #   contents   store paths merged into /, owned by root
  #   home       a store path holding the tree installed at `homePath`
  #   uid gid    the account's ids
  #   user group the account's names
  #   homePath   where `home` lands, e.g. "/home/dev"
  #
  # The base layer is built with `buildLayeredImage` — the part we know works.
  # The ownership happens in a second pass, where `fakeRootCommands` can be run
  # under fakeroot (or proot, where fakeroot cannot) and the tarball keeps the
  # ids the faked `chown` recorded. Only the home tree is chowned: /nix, /bin
  # and /etc stay root-owned, which is correct.
  userImage =
    {
      name,
      contents,
      extraCommands ? "",
      home,
      uid,
      gid,
      user,
      group,
      homePath,
      entrypoint,
      cmd ? [ ],
      env ? [ ],
    }:
    let
      base = layeredImage {
        inherit name contents extraCommands;
        entrypoint = [ "/bin/true" ];
      };
    in
    pkgs.dockerTools.buildImage {
      inherit name;
      fromImage = base;
      copyToRoot = home;
      fakeRootCommands = ''
        mkdir -p ${homePath}
        cp -r ${home}/. ${homePath}/
        chown -R ${toString uid}:${toString gid} ${homePath}
      '';
      chrootTools = [ pkgs.bashInteractive pkgs.coreutils ];
      config = {
        Entrypoint = entrypoint;
        Cmd = cmd;
        Env = env;
        WorkingDir = "/";
        User = user;
      };
    };

  # /etc/passwd and /etc/group for the one account a container image needs.
  #
  # A nix closure has no /etc at all. podman resolves `User=dev` through the
  # image's own passwd file — an unresolvable user is a start failure, not a
  # warning — and sshd looks the account up before it does anything else.
  account =
    { user, uid, gid, group, home, shell ? "/bin/sh" }:
    pkgs.runCommand "${user}-account" { } ''
      mkdir -p $out/etc
      {
        echo "root:x:0:0:root:/root:${shell}"
        echo "${user}:x:${toString uid}:${toString gid}:${user} (sandbox):${home}:${shell}"
      } > $out/etc/passwd
      {
        echo "root:x:0:"
        echo "${group}:x:${toString gid}:"
      } > $out/etc/group
    '';

  # The system CA bundle, at the path everything already points at.
  #
  # nixpkgs' `cacert` ships its bundle inside its own store path, and
  # NODE_EXTRA_CA_CERTS, REQUESTS_CA_BUNDLE and OpenSSL all expect
  # /etc/ssl/certs/ca-certificates.crt. So the file is placed there — and
  # *only* the public roots.
  #
  # The sandbox CA is not in here, and cannot be: it is generated per machine
  # and gitignored, so a flake cannot see it at all, and naming the folder would
  # pull the private key into the store (audit S2 — the leak the old Dockerfile
  # had through `COPY sandbox/ca/`). It is bind-mounted into the container
  # instead, read-only, and appended to this bundle at start.
  caTrustStore =
    pkgs.runCommand "sandbox-ca-trust-store" { } ''
      mkdir -p $out/etc/ssl/certs
      cp ${pkgs.cacert}/etc/ssl/certs/ca-certificates.crt \
         $out/etc/ssl/certs/ca-certificates.crt
      cp ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
         $out/etc/ssl/certs/ca-bundle.crt
    '';
}