{ config, lib, ... }:
{
  flake.modules.nixos.server-profile = {
    imports = [
      config.flake.modules.nixos.base-profile
      config.flake.modules.nixos.home-manager
      config.flake.modules.nixos.matyas

      config.flake.modules.nixos.alloy
    ];

    security.sudo = {
      execWheelOnly = true;
      wheelNeedsPassword = false;
    };

    networking = {
      firewall.enable = lib.mkDefault true;
      networkmanager.enable = lib.mkDefault false;
      nftables.enable = lib.mkDefault true;
      useDHCP = lib.mkDefault false;
      useHostResolvConf = lib.mkDefault false;
      useNetworkd = lib.mkDefault true;
    };

    services.openssh = {
      enable = true;

      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;

        LoginGraceTime = 30;
        MaxAuthTries = 3;
      };
    };

    home-manager.users.matyas.imports = [
      config.flake.modules.homeManager.matyas-server
    ];
  };
}
