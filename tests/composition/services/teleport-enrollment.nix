{ config, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem check failsEvaluation;
  modules = config.flake.modules.nixos;
  enrollment = {
    tokenName = "pilot-node";
    privateKeyFile = "/var/lib/teleport-enrollment/pilot.key";
  };
  node = (mkSystem [ modules.teleport-node modules.teleport-enrollment ] {
    deployment = {
      teleport-node = { proxyServer = "teleport.example.invalid:443"; labels = {}; };
      teleport-enrollment = enrollment;
    };
  }).config;
  inactive = (mkSystem [ modules.teleport-enrollment ] {}).config;
in
{
  flake.lib.compositionTests.teleport-enrollment = {
    joins-directly-with-bound-keypair = check "The node must use Teleport's native bound-keypair join with a private key file, not a token broker."
      (node.services.teleport.settings.teleport.join_params == {
        method = "bound_keypair";
        token_name = "pilot-node";
        bound_keypair.static_key_path = "/var/lib/teleport-enrollment/pilot.key";
      } && !node.services.openssh.enable
        && !(node.systemd.services.teleport.serviceConfig ? ExecStartPre)
        && !(node.systemd.services.teleport.serviceConfig ? ExecStartPost));
    inactive-needs-no-settings = check "Enrollment should do nothing if Teleport is disabled."
      (!inactive.services.teleport.enable && inactive.services.teleport.settings == {} && !inactive.services.openssh.enable);
    active-requires-key-reference = check "A selected enrollment feature requires a private key file path."
      (let missing = (mkSystem [ modules.teleport-enrollment ] {
        services.teleport.enable = true;
        deployment.teleport-enrollment.tokenName = "pilot-node";
      }).config;
      in failsEvaluation missing.services.teleport.settings);
  };
}
