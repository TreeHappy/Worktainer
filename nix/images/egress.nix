# sandbox-egress: the only way out of the sandbox to the internet.
#
# Replaces sandbox/egress/Dockerfile.
#
#   alpine:3.21 + iproute2 + nftables      -> pkgs.iproute2, pkgs.nftables
#   dnsmasq                                -> pkgs.dnsmasq
#   ca-certificates                         -> pkgs.cacert
#   python3 + py3-pip                      -> pkgs.python3
#   pip install mitmproxy==12.2.3          -> pkgs.mitmproxy
#   otel-cli 0.4.5 from a release tarball   -> pkgs.otel-cli
#
# Two of those are worth more than a package swap:
#
#   * **mitmproxy** was pinned to 12.2.3 in the Dockerfile because
#     auth_inject.py speaks its addon API. nixpkgs carries 12.2.3, so the pin
#     and the reason for it are now one `flake.lock` entry — and the "should a
#     future release stop shipping musllinux wheels, build from source" note in
#     that Dockerfile is gone with it, because there is no musl here.
#
#   * **otel-cli** and **dnsmasq** were release-tarball and apk installs whose
#     versions lived in ARG lines. They are ordinary attributes now.
#
# The scripts keep their historical absolute paths, because the entrypoint
# invokes /usr/local/bin/metrics.sh and mitmdump loads
# -s /usr/local/bin/auth_inject.py by name.
#
# What the controller does, and how to steer it, is in sandbox/egress/README.md.
{ pkgs, image }:
let
  bin = pkgs.runCommand "egress-bin" { } ''
    mkdir -p $out/bin $out/etc
    cp ${../../sandbox/egress/entrypoint.sh} $out/bin/entrypoint.sh
    cp ${../../sandbox/egress/metrics.sh} $out/bin/metrics.sh
    cp ${../../sandbox/egress/auth_inject.py} $out/bin/auth_inject.py
    cp ${../../sandbox/egress/dnsmasq.conf} $out/etc/dnsmasq.conf
    chmod 0755 $out/bin/entrypoint.sh $out/bin/metrics.sh
    chmod 0644 $out/bin/auth_inject.py $out/etc/dnsmasq.conf
  '';
in
image.layeredImage {
  name = "localhost/sandbox-egress";
  contents = image.rootClosure [
    pkgs.bashInteractive
    pkgs.cacert
    pkgs.coreutils # date, sleep, timeout
    pkgs.dnsmasq # the devbox's resolver
    pkgs.findutils
    pkgs.gawk
    pkgs.gnugrep
    pkgs.iproute2 # ip, tc, ss
    pkgs.mitmproxy # mitmdump, for the auth-injecting proxy
    pkgs.nftables # nft
    pkgs.otel-cli # the counter exporter
    pkgs.python3
    pkgs.which
    bin
  ];
  extraCommands = ''
    mkdir -p usr/local/bin
    cp -r ${bin}/bin/. usr/local/bin/
    cp ${bin}/etc/dnsmasq.conf etc/dnsmasq.conf
  '';
  entrypoint = [ "/usr/local/bin/entrypoint.sh" ];
}