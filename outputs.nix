inputs: let
  lib = import "${inputs.nixpkgs}/lib";
in
  inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [
      inputs.flake-parts.flakeModules.modules
      ((import inputs.import-tree).filterNot (lib.hasSuffix ".pkgs.nix") ./modules)
      inputs.flake-parts.flakeModules.touchup
    ];
    touchup.attr.modules.enable = false;
    _module.args.rootPath = ./.;
  }