{
  flake.modules.nixos.microvm-guest = { config, lib, ... }: {
    options.deployment.microvm.interfaceName = lib.mkOption {
      type = lib.types.str;
      description = "Name assigned to the guest virtio network interface.";
    };

    config = {
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

      services.openssh.hostKeys = lib.mkIf config.services.openssh.enable (lib.mkDefault [
        {
          type = "rsa";
          bits = 4096;
          path = "/var/lib/ssh/ssh_host_rsa_key";
        }
        {
          type = "ed25519";
          path = "/var/lib/ssh/ssh_host_ed25519_key";
        }
      ]);
      systemd.services = lib.mkIf config.services.openssh.enable {
        sshd.unitConfig.RequiresMountsFor = [ "/var/lib/ssh" ];
        sshd-keygen = lib.mkIf config.services.openssh.generateHostKeys {
          unitConfig.RequiresMountsFor = [ "/var/lib/ssh" ];
        };
      };

      systemd.network = {
        enable = true;
        links."10-lan" = {
          matchConfig.Driver = "virtio_net";
          linkConfig = {
            NamePolicy = "";
            Name = config.deployment.microvm.interfaceName;
          };
        };

        networks.lan = {
          matchConfig = {
            Type = "ether";
            Name = config.deployment.microvm.interfaceName;
          };

          networkConfig.DHCP = lib.mkDefault "ipv4";
        };
      };
    };
  };
}
