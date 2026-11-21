{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem extend check;
  modules = config.flake.modules.nixos;
  active = mkSystem [ modules.base-profile ] {};
  external = extend active { nixpkgs.pkgs = active.pkgs; };
  custom = extend active {
    time.timeZone = "Europe/Prague";
    nix.gc = { dates = "daily"; options = "--delete-older-than 7d"; };
    services.timesyncd.enable = false;
  };
in
{
  flake.lib.compositionTests.base-profile = {
    allows-all-unfree-packages = check "Base policy should allow all unfree packages in the effective NixOS package set."
      ((active.config.nixpkgs.config.allowUnfree or false) && (active.pkgs.config.allowUnfree or false));
    standalone-homes-allow-all-unfree-packages = check "Standalone Home Manager outputs should also allow all unfree packages."
      (lib.all (home: home.pkgs.config.allowUnfree or false)
        (builtins.attrValues config.flake.homeConfigurations));
    supports-inherited-package-sets = check "Systems reusing a package set should inherit its unfree policy without reconfiguring Nixpkgs."
      (external.config.nixpkgs.config == {} && (external.pkgs.config.allowUnfree or false));
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
