{ config, lib, ... }:
{
  flake.modules.nixos.microvm-profile = {
    imports = [
      config.flake.modules.nixos.base-profile
    ];

    microvm.shares = [
      {
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        tag = "ro-store";
        proto = "virtiofs";
      }
    ];

    networking.useDHCP = false;

    systemd.network = {
      enable = true;

      networks.lan = {
        matchConfig.Type = "ether";

        networkConfig = {
          DHCP = lib.mkDefault "ipv4";
        };
      };
    };

    system.stateVersion = "26.05";
  };
}