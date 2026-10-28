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
    system = "aarch64-darwin";
  in
  {
    devShells."${system}".default = let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ zig.overlays.default ];
      };
    in pkgs.mkShell {
      packages = with pkgs; [
        git

        nixd
        nixfmt

        zls
        zigpkgs."0.17.0"
      ];
    };
  };
}
