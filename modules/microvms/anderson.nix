{ config, ... }:
{
  # Internal DNS and DHCP server
  flake.modules.nixos.anderson = {
    imports = [
      config.flake.modules.nixos.microvm-profile

      config.flake.modules.nixos.tailscale-microvm
      config.flake.modules.nixos.tailscale-dns
    ];

    microvm = {
      hypervisor = "qemu";

      vcpu = 1;
      mem = 512;

      volumes = [
        {
          image = "anderson-tailscale.img";
          mountPoint = "/var/lib/tailscale";
          size = 128;
        }
      ];

      interfaces = [
        {
          type = "tap";
          id = "vm-anderson";
          mac = "02:00:00:00:00:01";
        }
      ];
    };
    
    networking.hostName = "anderson";

    services.openssh = {
      enable = true;

      settings.PasswordAuthentication = true;
    };

    users.users.test = {
      isNormalUser = true;

      password = "password";

      extraGroups = [ "wheel" ];
    };
  };
}