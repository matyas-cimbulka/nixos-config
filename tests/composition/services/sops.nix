{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem check;
  modules = config.flake.modules.nixos;
  active = mkSystem [ modules.sops ] {};
in
{
  flake.lib.compositionTests.sops = {
    enables-systemd-delivery = check "The SOPS feature should select systemd activation for runtime secret delivery."
      active.config.sops.useSystemdActivation;
    adds-no-deployment-secrets = check "The reusable SOPS feature should leave secret selection to deployment."
      (active.config.sops.secrets == {} && active.config.sops.templates == {});
  };
}
