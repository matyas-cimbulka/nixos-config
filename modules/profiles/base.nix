{ lib, ... }:
{
  flake.modules.nixos.base-profile = { options, ... }: {
    # MicroVMs reuse their host's configured package set.
    nixpkgs.config = lib.mkIf (!options.nixpkgs.pkgs.isDefined) { allowUnfree = true; };

    nix = {
      settings.experimental-features = [ "nix-command" "flakes" ];

      gc = {
        automatic = true;
        dates = lib.mkDefault "weekly";
        options = lib.mkDefault "--delete-older-than 15d";
      };
    };

    time = {
      timeZone = lib.mkDefault "UTC";
      hardwareClockInLocalTime = lib.mkDefault false;
    };

    services.timesyncd.enable = lib.mkDefault true;
  };
}
