{ config, lib, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos.server-profile = { config, ... }: {
    imports = [
      flakeConfig.flake.modules.nixos.base-profile

      flakeConfig.flake.modules.nixos.sops
      flakeConfig.flake.modules.nixos.tailscale-server
      flakeConfig.flake.modules.nixos.alloy
    ];
    
    assertions = [
      {
        assertion = config.networking.nameservers != [ ];
        message = "The server profile requires explicit networking.nameservers";
      }
    ];

    security.sudo = {
      execWheelOnly = true;
      wheelNeedsPassword = false;
    };

    boot.loader.grub.configurationLimit = 15;

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
  };
}
