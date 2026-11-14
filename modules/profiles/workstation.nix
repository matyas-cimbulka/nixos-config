{ config, lib, ... }:
{
  flake.modules.nixos.workstation-profile = {
    imports = [
      config.flake.modules.nixos.base-profile
      config.flake.modules.nixos.home-manager
      config.flake.modules.nixos.matyas
    ];

    security.sudo.execWheelOnly = true;

    networking = {
      firewall.enable = lib.mkDefault true;
      networkmanager.enable = lib.mkDefault true;
      nftables.enable = lib.mkDefault true;
      useDHCP = lib.mkDefault false;
      useNetworkd = lib.mkDefault false;
    };

    users.users.matyas.extraGroups = [ "networkmanager" ];

    home-manager.users.matyas.imports = [
      config.flake.modules.homeManager.matyas-workstation
    ];
  };
}
