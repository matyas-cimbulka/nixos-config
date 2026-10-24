{ config, ... }:
{
  flake.modules.nixos.server-profile = {
    imports = [
      config.flake.modules.nixos.base-profile
      config.flake.modules.nixos.matyas
    ];

    security.sudo = {
      execWheelOnly = true;
      wheelNeedsPassword = false;
    };

    boot.loader.grub.configurationLimit = 15;

    services.openssh.enable = true;
  };
}
