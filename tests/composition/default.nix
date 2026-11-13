{ inputs, config, lib, ... }:
let
  helpers = import ./helpers.nix { inherit inputs; };
in
{
  imports = [
    ((import inputs.import-tree).filterNot
      (path: builtins.elem (builtins.baseNameOf path) [ "default.nix" "helpers.nix" ])
      ./.)
  ];
  options.flake.lib.compositionTests = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.lazyAttrsOf lib.types.bool);
    default = {};
    description = "Named composition suites containing evaluation-time test results.";
  };

  config = {
    _module.args.compositionHelpers = helpers;
    systems = lib.mkDefault [ helpers.system ];
    perSystem = { pkgs, system, ... }: {
      checks = lib.optionalAttrs (system == helpers.system) (lib.mapAttrs'
        (suite: results: lib.nameValuePair "composition-${suite}" (
          # Force expectations before constructing the derivation, so --no-build
          # runs the assertions too. The build only creates a success marker.
          assert lib.assertMsg (lib.all (result: result == true) (builtins.attrValues results))
            "Composition suite ${suite} contains a failing result.";
          pkgs.runCommand "composition-${suite}" {} ''touch "$out"''
        ))
        config.flake.lib.compositionTests);
    };
  };
}
