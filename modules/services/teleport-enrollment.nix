{
  flake.modules.nixos.teleport-enrollment = { config, lib, ... }:
    let
      cfg = config.deployment.teleport-enrollment;
    in
    {
      options.deployment.teleport-enrollment = {
        tokenName = lib.mkOption {
          type = lib.types.strMatching "[A-Za-z0-9][A-Za-z0-9._-]*";
          description = "Name of this node's bound-keypair token resource in Teleport. This is not a secret.";
        };
        privateKeyFile = lib.mkOption {
          type = lib.types.strMatching "/(run|var/lib)/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*";
          description = "Runtime path to the root-only static enrollment key, provisioned outside the Nix store.";
        };
      };

      config = lib.mkIf config.services.teleport.enable {
        services.teleport.settings.teleport.join_params = {
          method = "bound_keypair";
          token_name = cfg.tokenName;
          bound_keypair.static_key_path = cfg.privateKeyFile;
        };
      };
    };
}
