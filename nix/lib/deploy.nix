# Where each config file goes.
#
# The direct replacement for mise's `[dotfiles]` section: the same targets, one
# entry per file rather than per directory, because that is what the section
# expanded to anyway (six entries were `symlink-each`, which deploys one symlink
# per file).
#
# Written out in full rather than derived by a convention, because the targets
# are not derivable: `starship.toml` is the odd one out, `bat` is a directory
# while `opencode` is two files in one directory, and the vendored Catppuccin
# theme carries a space in its filename.
{
  # source path under nix/configs/files -> path relative to $HOME
  targets = {
    "bashrc" = ".bashrc";

    "atuin/config.toml" = ".config/atuin/config.toml";
    "bat/config" = ".config/bat/config";
    "bat/themes/Catppuccin Frappe.tmTheme" = ".config/bat/themes/Catppuccin Frappe.tmTheme";
    "eza/theme.yml" = ".config/eza/theme.yml";
    "hunk/config.toml" = ".config/hunk/config.toml";
    "jjui/config.toml" = ".config/jjui/config.toml";
    "jjui/themes/catppuccin-frappe.toml" = ".config/jjui/themes/catppuccin-frappe.toml";
    "lazygit/config.yml" = ".config/lazygit/config.yml";
    "leaf/config.toml" = ".config/leaf/config.toml";
    "leaf/themes/catppuccin-frappe.toml" = ".config/leaf/themes/catppuccin-frappe.toml";
    "opencode/cli.json" = ".config/opencode/cli.json";
    "opencode/opencode.json" = ".config/opencode/opencode.json";
    "pi/settings.json" = ".pi/agent/settings.json";
    "pi/themes/catppuccin-frappe.json" = ".pi/agent/themes/catppuccin-frappe.json";
    "procs/config.toml" = ".config/procs/config.toml";
    "starship.toml" = ".config/starship.toml";
    "workmux/config.yaml" = ".config/workmux/config.yaml";
    "yazi/theme.toml" = ".config/yazi/theme.toml";
    "yazi/yazi.toml" = ".config/yazi/yazi.toml";
    "yazi/flavors/catppuccin-frappe.yazi/flavor.toml" = ".config/yazi/flavors/catppuccin-frappe.yazi/flavor.toml";
    "yazi/flavors/catppuccin-frappe.yazi/tmtheme.xml" = ".config/yazi/flavors/catppuccin-frappe.yazi/tmtheme.xml";
    "zellij/config.kdl" = ".config/zellij/config.kdl";

    # Shipped, but not deployed anywhere by this table: the license and readme
    # that belong beside yazi's vendored flavor.
    "yazi/flavors/catppuccin-frappe.yazi/LICENSE" = ".config/yazi/flavors/catppuccin-frappe.yazi/LICENSE";
    "yazi/flavors/catppuccin-frappe.yazi/LICENSE-tmtheme" = ".config/yazi/flavors/catppuccin-frappe.yazi/LICENSE-tmtheme";
    "yazi/flavors/catppuccin-frappe.yazi/README.md" = ".config/yazi/flavors/catppuccin-frappe.yazi/README.md";
  };

  # Devbox-only. The host has no reason to run an sshd from this repo — the
  # devbox's is unprivileged and listens on 2222 inside a container — so this
  # is a separate table and not a flag on the one above.
  imageOnly = {
    "sshd/sshd_config" = ".ssh/sshd/sshd_config";
  };
}