{
  description = "NixOS configuration for Retroid Pocket 5 (Snapdragon 865/SM8250)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, ... }@inputs:
    let
      system = "aarch64-linux";

      # Nixpkgs with allowUnfree and our overlays
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          # Allow broken packages (some ARM packages may be marked broken)
          allowBroken = true;
        };
        overlays = [
          self.overlays.default
          # Unstable packages overlay
          (final: prev: {
            unstable = import nixpkgs-unstable {
              inherit system;
              config.allowUnfree = true;
            };
          })
        ];
      };

      # Helper to create NixOS system
      mkSystem = { hostname, extraModules ? [] }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs pkgs;
            flake = self;
          };
          modules = [
            ./hosts/${hostname}
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
            }
          ] ++ extraModules;
        };

    in {
      # NixOS configurations
      nixosConfigurations = {
        rp5 = mkSystem {
          hostname = "rp5";
        };
      };

      # Package overlays
      overlays.default = import ./overlays;

      # Development shell for working on the configuration
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          nixpkgs-fmt
          nil  # Nix LSP
          nix-tree
          nix-diff
        ];
      };

      # Expose packages we build
      packages.${system} = {
        # Helper to build the system
        system = self.nixosConfigurations.rp5.config.system.build.toplevel;
      };
    };
}
