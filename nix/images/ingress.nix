# sandbox-ingress: the only way into the sandbox from the host.
#
# Replaces sandbox/ingress/Dockerfile. What that file did with `apk add` and a
# curl of an otel-cli release tarball, this does with nixpkgs attributes — which
# is also how the otel-cli version stops being a build ARG somebody has to
# remember to bump. nixpkgs currently carries otel-cli 0.4.5, the same version
# the ARG pinned.
#
#   alpine:3.21 + iproute2 + nftables      -> pkgs.iproute2, pkgs.nftables
#   ca-certificates                         -> pkgs.cacert
#   otel-cli 0.4.5 from a release tarball   -> pkgs.otel-cli
#   alpine's /bin/sh (busybox ash)          -> nix/lib/image.nix `sh` (bash)
#
# The scripts keep their historical absolute paths: the entrypoint runs
# /usr/local/bin/metrics.sh by that name, and `bin/check` execs into the
# container by hand.
#
# What the controller does, and how to steer it, is in
# sandbox/ingress/README.md.
{ pkgs, image }:
let
  bin = pkgs.runCommand "ingress-bin" { } ''
    mkdir -p $out/bin
    cp ${../../sandbox/ingress/entrypoint.sh} $out/bin/entrypoint.sh
    cp ${../../sandbox/ingress/metrics.sh} $out/bin/metrics.sh
    chmod 0755 $out/bin/entrypoint.sh $out/bin/metrics.sh
  '';
in
image.layeredImage {
  name = "localhost/sandbox-ingress";
  contents = image.rootClosure [
    pkgs.bashInteractive
    pkgs.cacert
    pkgs.coreutils # date, sleep, timeout
    pkgs.gawk # the counter scrape
    pkgs.gnugrep
    pkgs.iproute2 # ip, tc, ss
    pkgs.nftables # nft
    pkgs.otel-cli # the counter exporter
    bin
  ];
  extraCommands = ''
    mkdir -p usr/local/bin
    cp -r ${bin}/bin/. usr/local/bin/
  '';
  entrypoint = [ "/usr/local/bin/entrypoint.sh" ];
}