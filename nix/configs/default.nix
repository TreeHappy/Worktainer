# Every config file this repo ships, keyed by its path under `files/`.
#
# Read with `builtins.readFile` rather than pasted into Nix strings. The tree is
# TOML, KDL, JSON, YAML and two copies of a 2000-line tmTheme, and escaping
# that by hand into `''...''` is a trap: a literal quote next to an
# interpolation becomes `'''${`, which Nix reads as an escaped `''` followed by
# a *real* interpolation. Reading the file is lossless, and the content stays
# reviewable as the text it is.
#
# Consumed by both sides of the sandbox:
#
#   host    `nix/lib/deploy.nix` -> home-manager `home.file`, into $HOME
#   devbox  `nix/images/devbox.nix` -> /home/dev in the image
#
# The only consumer difference is the target list, not the content.
{ }:
let
  f = path: builtins.readFile (./files + "/${path}");
in
{
  "bashrc" = f "bashrc";
  "starship.toml" = f "starship.toml";

  "atuin/config.toml" = f "atuin/config.toml";
  "bat/config" = f "bat/config";
  # bat and yazi want the same vendored Catppuccin Frappé theme under two
  # different names, and the two copies are byte-identical (md5
  # df4cce05d64bddf570fc081e280f0566). One file, two keys — the todo's "written
  # once" actually holding for the one place it can.
  "bat/themes/Catppuccin Frappe.tmTheme" = f "bat/themes/Catppuccin Frappe.tmTheme";
  "yazi/flavors/catppuccin-frappe.yazi/tmtheme.xml" =
    f "yazi/flavors/catppuccin-frappe.yazi/tmtheme.xml";
  "eza/theme.yml" = f "eza/theme.yml";
  "hunk/config.toml" = f "hunk/config.toml";
  "jjui/config.toml" = f "jjui/config.toml";
  "jjui/themes/catppuccin-frappe.toml" = f "jjui/themes/catppuccin-frappe.toml";
  "lazygit/config.yml" = f "lazygit/config.yml";
  "leaf/config.toml" = f "leaf/config.toml";
  "leaf/themes/catppuccin-frappe.toml" = f "leaf/themes/catppuccin-frappe.toml";
  "opencode/cli.json" = f "opencode/cli.json";
  "opencode/opencode.json" = f "opencode/opencode.json";
  "pi/settings.json" = f "pi/settings.json";
  "pi/themes/catppuccin-frappe.json" = f "pi/themes/catppuccin-frappe.json";
  "procs/config.toml" = f "procs/config.toml";
  "workmux/config.yaml" = f "workmux/config.yaml";
  "yazi/theme.toml" = f "yazi/theme.toml";
  "yazi/yazi.toml" = f "yazi/yazi.toml";
  "yazi/flavors/catppuccin-frappe.yazi/flavor.toml" =
    f "yazi/flavors/catppuccin-frappe.yazi/flavor.toml";
  "zellij/config.kdl" = f "zellij/config.kdl";

  # Image-only: the devbox's sshd config is never deployed to a host. See
  # nix/lib/deploy.nix, where the host target list simply omits it.
  "sshd/sshd_config" = f "sshd/sshd_config";

  # Not deployed anywhere, kept because they are part of the vendored flavor
  # yazi expects to find beside it.
  "yazi/flavors/catppuccin-frappe.yazi/LICENSE" =
    f "yazi/flavors/catppuccin-frappe.yazi/LICENSE";
  "yazi/flavors/catppuccin-frappe.yazi/LICENSE-tmtheme" =
    f "yazi/flavors/catppuccin-frappe.yazi/LICENSE-tmtheme";
  "yazi/flavors/catppuccin-frappe.yazi/README.md" =
    f "yazi/flavors/catppuccin-frappe.yazi/README.md";
}