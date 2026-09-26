{
  description = "Nix flake for the Baseten CLI (prebuilt upstream binaries)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          baseten = pkgs.callPackage ./packages/baseten/package.nix { };
          default = self.packages.${system}.baseten;
        }
      );

      apps = forAllSystems (system: {
        baseten = {
          type = "app";
          program = "${self.packages.${system}.baseten}/bin/baseten";
        };
        default = self.apps.${system}.baseten;
      });

      overlays.default = _final: prev: {
        baseten = prev.callPackage ./packages/baseten/package.nix { };
      };

      nixosModules.baseten =
        { config, lib, pkgs, ... }:
        let
          cfg = config.programs.baseten;
        in
        {
          options.programs.baseten = {
            enable = lib.mkEnableOption "the Baseten CLI";
            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.baseten;
              defaultText = lib.literalExpression "baseten-flake.packages.\${system}.baseten";
              description = "The baseten package to install.";
            };
          };

          config = lib.mkIf cfg.enable {
            environment.systemPackages = [ cfg.package ];
          };
        };
      nixosModules.default = self.nixosModules.baseten;

      homeModules.baseten =
        { config, lib, pkgs, ... }:
        let
          cfg = config.programs.baseten;
        in
        {
          options.programs.baseten = {
            enable = lib.mkEnableOption "the Baseten CLI";
            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.baseten;
              defaultText = lib.literalExpression "baseten-flake.packages.\${system}.baseten";
              description = "The baseten package to install.";
            };
          };

          config = lib.mkIf cfg.enable {
            home.packages = [ cfg.package ];
          };
        };
      homeModules.default = self.homeModules.baseten;
    };
}
