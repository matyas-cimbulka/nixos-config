{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem extend check;
  modules = config.flake.modules.nixos;
  active = mkSystem [ modules.base-profile ] {};
  custom = extend active {
    time.timeZone = "Europe/Prague";
    nix.gc = { dates = "daily"; options = "--delete-older-than 7d"; };
    services.timesyncd.enable = false;
  };
in
{
  flake.lib.compositionTests.base-profile = {
    supplies-nix-cli-features = check "The base profile should provide flakes and the new Nix CLI."
      (builtins.elem "flakes" active.config.nix.settings.experimental-features
        && builtins.elem "nix-command" active.config.nix.settings.experimental-features);
    deployment-overrides-policy-defaults = check "Deployments should be able to override base timezone, garbage-collection schedule, and time synchronization."
      (custom.config.time.timeZone == "Europe/Prague"
        && custom.config.nix.gc.dates == [ "daily" ] && custom.config.nix.gc.options == "--delete-older-than 7d"
        && !custom.config.services.timesyncd.enable);
    leaves-feature-selection-to-other-profiles = check "Base policy should not enable application, network identity, or observability features."
      (!active.config.services.alloy.enable && !active.config.services.tailscale.enable
        && !active.config.virtualisation.docker.enable && !(active.config.users.users ? matyas));
  };
}
