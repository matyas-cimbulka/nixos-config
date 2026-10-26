{ lib, ... }:
{
  flake.modules.nixos.base-profile = {
    nix = {
      settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      gc = {
        automatic = true;
        dates = lib.mkDefault "weekly";
        options = lib.mkDefault "--delete-older-than 15d";
      };
    };

    boot.loader.grub.configurationLimit = lib.mkDefault 10;

    time = {
      timeZone = lib.mkDefault "UTC";
      hardwareClockInLocalTime = lib.mkDefault false;
    };

    services.timesyncd.enable = lib.mkDefault true;
  };
}
