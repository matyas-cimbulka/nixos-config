{ inputs, config, lib, ... }:
let
  targetSystem = config.flake.nixosConfigurations.tycho.config.nixpkgs.hostPlatform.system;
in
{
  imports = [
    ((import inputs.import-tree).filterNot
      (path: builtins.elem (builtins.baseNameOf path) [ "default.nix" "helpers.nix" ])
      ./.)
  ];
  options.flake.lib.deploymentTests = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.lazyAttrsOf lib.types.bool);
    default = {};
    description = "Evaluation tests for actual deployments.";
  };

  config = {
    _module.args.deploymentHelpers = import ./helpers.nix {
      inherit lib;
      host = config.flake.nixosConfigurations.tycho.config;
    };
    perSystem = { pkgs, system, ... }: {
      checks = lib.optionalAttrs (system == targetSystem) (lib.mapAttrs'
        (suite: results: lib.nameValuePair "deployment-${suite}" (
          # Assertions run during evaluation, including flake check --no-build.
          assert lib.assertMsg (lib.all (result: result == true) (builtins.attrValues results))
            "Deployment suite ${suite} contains a failing result.";
          pkgs.runCommand "deployment-${suite}" {} ''touch "$out"''
        ))
        config.flake.lib.deploymentTests);
    };
  };
}
