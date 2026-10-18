# Host entry points.
#
# One file per machine, named after the machine, holding only what is actually
# machine-specific. Everything else — the tools, the config, the targets — lives
# in modules/ and is shared.
#
# To set this up:
#
#   cp nix/hosts/example.nix nix/hosts/$(hostname -s).nix
#   $EDITOR nix/hosts/$(hostname -s).nix      # set `user`
#   home-manager switch --flake ./nix#$(hostname -s)
#
# The flake reads this directory and emits one homeConfiguration per file, so
# the filename is the only registration step. The example itself is inert: it is
# named `example`, so it produces a configuration called `example` and nobody
# switches to it by accident.
{ ... }:
{
  # The account to deploy into. This is the one value that cannot be shared,
  # and the reason this file exists at all.
  home.username = "your-username";
  home.homeDirectory = "/home/your-username";

  # The schema home-manager migrates activations against. Required from 24.11
  # onwards; bump it when upgrading across a release that changes options.
  home.stateVersion = "24.11";
}