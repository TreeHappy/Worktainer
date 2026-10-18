# The toolchain: 27 tools, the same set mise installs from `[tools]`.
#
# This is an attrset rather than a list of names, and that is the whole point.
# Five of the 27 do not live under the attribute name mise gave them, and one
# is not in nixpkgs at all:
#
#   jj      -> jujutsu              nixpkgs `jj` is tidwall/jj, a JSON tool
#   yq      -> yq-go                nixpkgs `yq` is the Python one
#   leaf    -> leaf-markdown-viewer renamed upstream, same project
#   pi      -> pi-coding-agent      renamed upstream, same project
#   node    -> nodejs_22            `nodejs` is a moving default
#   workmux -> (no nixpkgs package) upstream ships its own flake, see below
#
# A `map (name: pkgs.${name})` over the mise list gets all six wrong, and all
# five that resolve *build* — `pkgs.jj` and `pkgs.yq` each produce a working
# binary that is simply the wrong program. There is no failure to notice.
#
# Every attribute below was evaluated against nixpkgs, not grepped: see
# nix/README.md for the check and the versions it produced.
#
#   host   the 27, for the machine you work on
#   image  the 27 plus openbao, for the devbox
{
  pkgs,
  workmux,
}:
let
  inherit (pkgs)
    atuin
    bat
    carapace
    duf
    dust
    eza
    fd
    fzf
    gh
    hunk
    jujutsu
    jjui
    jq
    lazygit
    leaf-markdown-viewer
    neovim
    nodejs_22
    opencode
    pi-coding-agent
    procs
    ripgrep
    starship
    yazi
    yq-go
    zellij
    zoxide
    ;
in
rec {
  # The toolchain as mise installed it: same 27 tools, same names on PATH.
  host = {
    atuin = atuin;
    bat = bat;
    carapace = carapace;
    duf = duf;
    dust = dust;
    eza = eza;
    fd = fd;
    fzf = fzf;
    gh = gh;

    # Terminal markdown previewer — leaf.rivolink.mg.
    leaf = leaf-markdown-viewer;
    hunk = hunk;

    # The VCS. Not nixpkgs' `jj`, which is tidwall's JSON stream editor.
    jj = jujutsu;
    jjui = jjui;
    jq = jq;
    lazygit = lazygit;
    neovim = neovim;

    # A major version, deliberately: `nodejs` itself is a moving default, so
    # pinning it would defeat the point of pinning.
    node = nodejs_22;
    opencode = opencode;

    # pi.dev
    pi = pi-coding-agent;
    procs = procs;
    ripgrep = ripgrep;
    starship = starship;
    yazi = yazi;

    # mikefarah's Go implementation, which is what mise was installing.
    yq = yq-go;
    zellij = zellij;
    zoxide = zoxide;

    # Not in nixpkgs. raine/workmux ships its own flake, so it is a flake
    # input and flake.lock pins it like everything else.
    workmux = workmux;
  };

  # The devbox's toolchain: the same 27 plus the OpenBao CLI, which
  # `sshd-init` uses to fetch its authorized keys from the sandbox's secrets
  # server. There is no OpenBao service in the host stack — only in the
  # sandbox — so it stays out of `host`.
  image = host // {
    openbao = pkgs.openbao;
  };
}