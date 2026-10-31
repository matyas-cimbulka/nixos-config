{ config, lib, ... }:
{
  flake.modules.nixos.microvm-profile = {
    imports = [
      config.flake.modules.nixos.base-profile
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

    networking.useDHCP = false;

    systemd.network = {
      enable = true;

      networks.lan = {
        matchConfig = {
            Type = "ether";
            Name = "en* eth*";
          };

        networkConfig = {
          DHCP = lib.mkDefault "ipv4";
        };
      };
    };

    system.stateVersion = "26.05";
  };
}