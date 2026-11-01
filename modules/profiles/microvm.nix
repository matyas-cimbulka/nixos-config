{ config, lib, ... }:
{
  flake.modules.nixos.microvm-profile = {
    imports = [
      config.flake.modules.nixos.base-profile

      config.flake.modules.nixos.alloy
    ];

    microvm = {
      volumes = [
        {
          image = "ssh-host-keys.img";
          mountPoint = "/var/lib/ssh";
          size = 32;
        }
      ];
      
      shares = [
        {
          source = "/nix/store";
          mountPoint = "/nix/.ro-store";
          tag = "ro-store";
          proto = "virtiofs";
        }
      ];
    };

    networking = {
      useDHCP = false;

      firewall.interfaces."lan0".allowedTCPPorts = [ 12345 ];
    };

    systemd.network = {
      enable = true;

      links."10-lan" = {
        matchConfig.Driver = "virtio_net";

        linkConfig = {
          NamePolicy = "";
          Name = "lan0";
        };
      };

      networks.lan = {
        matchConfig = {
            Type = "ether";
            Name = "lan0";
          };

        networkConfig = {
          DHCP = lib.mkDefault "ipv4";
        };
      };
    };

    system.stateVersion = "26.05";
  };
}