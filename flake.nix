{
  description = "sandbox — a devbox whose every packet in and out crosses a controller";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # The host's tools and configuration. Nothing in the containers uses this:
    # an image is fixed at build time, so it writes its config rather than
    # deploying a profile.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # workmux is not in nixpkgs. Upstream ships its own flake, so this is how
    # it gets pinned like everything else instead of being an unpinned
    # `cargo install`.
    workmux = {
      url = "github:raine/workmux";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      workmux,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # Read a host file by name: nix/hosts/<hostname>.nix. The basename is the
      # machine and it is the only registration step — see
      # nix/hosts/example.nix. `readDir` hands back the file names, so the
      # extension comes off here and is put back on for the module path.
      hostFiles =
        let
          names = builtins.attrNames (builtins.readDir ./nix/hosts);
        in
        builtins.listToAttrs (
          map (file: {
            name = nixpkgs.lib.removeSuffix ".nix" file;
            value = ./nix/hosts + "/${file}";
          }) (builtins.filter (file: file != "default.nix") names)
        );

      # The pieces every system needs, wired together once.
      mkPkgs = system: nixpkgs.legacyPackages.${system};

      mkTools =
        pkgs:
        import ./nix/lib/tools.nix {
          inherit pkgs;
          workmux = workmux.packages.${pkgs.stdenv.hostPlatform.system}.default;
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
          lib = pkgs.lib;

          tools = mkTools pkgs;
          configs = import ./nix/configs/default.nix { };
          image = import ./nix/lib/image.nix { inherit pkgs lib; };
        in
        rec {
          # Everything the host installs, as one closure. Useful for
          # `nix build ./nix#host-tools` and for asking what a change did; the
          # way it actually reaches PATH is the home-manager profile below.
          host-tools = pkgs.buildEnv {
            name = "sandbox-host-tools";
            paths = builtins.attrValues tools.host ++ [ pkgs.git ];
          };

          # The three images this repo owns, as docker-format tarballs for
          # `podman load`. The other four containers in the stack are upstream
          # images (openbao, o11ylite, otel-desktop-viewer, otelop), pulled
          # rather than built here.
          sandbox-ingress = import ./nix/images/ingress.nix { inherit pkgs image; };
          sandbox-egress = import ./nix/images/egress.nix { inherit pkgs image; };
          sandbox-devbox = import ./nix/images/devbox.nix {
            inherit pkgs lib image configs;
            tools = tools.image;
            targets = (import ./nix/lib/deploy.nix).targets;
            imageTargets = (import ./nix/lib/deploy.nix).imageOnly;
          };

          # All three at once, which is what `bin/sandbox build` asks for.
          sandbox-images = pkgs.buildEnv {
            name = "sandbox-images";
            paths = [
              sandbox-ingress
              sandbox-egress
              sandbox-devbox
            ];
          };

          default = sandbox-images;
        }
      );

      # One homeConfiguration per file in nix/hosts/, for every system:
      #
      #   cp nix/hosts/example.nix nix/hosts/$(hostname -s).nix
      #   home-manager switch --flake ./nix#$(hostname -s)
      homeConfigurations = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
        in
        builtins.mapAttrs (
          host: path:
          home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              ./nix/modules/host.nix
              path
            ];
            extraSpecialArgs = {
              tools = (mkTools pkgs).host;
              configs = import ./nix/configs/default.nix { };
              targets = (import ./nix/lib/deploy.nix).targets;
            };
          }
        ) hostFiles
      );

      # `nix flake check` evaluates these, so a typo in an attribute name fails
      # here rather than at the first `nix build`.
      checks = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
          tools = mkTools pkgs;
        in
        {
          tools-resolve = pkgs.runCommand "tools-resolve" { } ''
            echo "host tools: ${builtins.concatStringsSep " " (builtins.attrNames tools.host)}"
            echo "image tools: ${builtins.concatStringsSep " " (builtins.attrNames tools.image)}"
            touch $out
          '';
        }
      );

      formatter = forAllSystems (system: (mkPkgs system).nixpkgs-fmt);
    };
}