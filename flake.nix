{
  description = "mimiqu flake";

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
    packages = forAllPlatforms ( pkgs: {
      protos = pkgs.runCommand "mimiqu-protos" {} ''
        mkdir -p "$out"
        cp -R ${./proto}/. "$out/"
      '';
    });

    devShells = forAllPlatforms ( pkgs: {
      default = pkgs.mkShell {
        packages = with pkgs; [
          git
          docker-compose

          buf

          nixd
          nixfmt

          zls
          zigpkgs."0.17.0"

          cmake
          ninja
        ];
      };
    });
  };
}
