{
  description = "mimique flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    zig = {
      url = "github:mitchellh/zig-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs = { self, nixpkgs, zig, ... }: let
    platforms = [
      "x86_64-linux"
      "aarch64-darwin"
    ];

    forAllPlatforms = f: nixpkgs.lib.genAttrs platforms (
      system: f (import nixpkgs {
        inherit system;
        overlays = [ zig.overlays.default ];
      })
    );

  in
  {
    devShells = forAllPlatforms ( pkgs: {
      default = pkgs.mkShell {
        packages = with pkgs; [
          git

          nixd
          nixfmt

          zls
          zigpkgs."0.17.0"
        ];
      };
    });
  };
}
