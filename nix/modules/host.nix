# The host module: the 27 tools and the config files, deployed by
# home-manager.
#
# This is what mise's `[tools]` and `[dotfiles]` sections did, and the split
# between the two is preserved: `tools.nix` decides *what* is installed,
# `deploy.nix` decides *where* the config lands, and `configs/default.nix`
# holds the content both the host and the devbox image read.
#
# Nothing here is sandbox-specific. The devbox image builds the same content
# through `nix/images/devbox.nix`, not through this module: an image is fixed
# at build time, so it writes files rather than deploying a profile.
{
  config,
  lib,
  pkgs,
  tools ? { },
  configs ? { },
  targets ? { },
  ...
}:
let
  inherit (lib) attrValues mapAttrs';
in
{
  # The toolchain, plus git.
  #
  # git is in nixpkgs and was not in mise's registry, which is why
  # docs/new-machine.md told you to install it by hand. jj, jjui, lazygit and
  # workmux all shell out to it, so it is a dependency rather than a choice.
  #
  # Installed into ~/.nix-profile and put on PATH by home-manager; the bashrc
  # additionally prepends the profile, because that file also runs before a
  # profile switch has ever happened on a fresh machine.
  home.packages = attrValues tools ++ [ pkgs.git ];

  # One `home.file` per config file.
  #
  # `text` rather than `source`, deliberately: home-manager copies the content,
  # while a `source` string would symlink into the store — read-only, so
  # `nvim ~/.config/zellij/config.kdl` would fail to save. mise symlinked into
  # the checkout, which is editable; the equivalent here is a copy.
  home.file = mapAttrs' (source: target: {
    name = "${config.home.homeDirectory}/${target}";
    value.text = configs.${source};
  }) targets;

  # `$HOME/.local/bin` is not on PATH in a fresh nix profile, and the bashrc's
  # tool init lines assume nothing exotic — but `~/.local/bin` is where a user
  # drops their own scripts, so it stays on PATH for the same reason it was
  # under mise.
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}