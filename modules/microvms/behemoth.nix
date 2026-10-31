{ config, ... }:
{
  flake.modules.nixos.behemoth = { lib, ... }: {
    imports = [
      config.flake.modules.nixos.microvm-profile

      config.flake.modules.nixos.tailscale-microvm
      config.flake.modules.nixos.docker

      config.flake.modules.nixos.traefik
      config.flake.modules.nixos.pocket-id
    ];

    microvm = {
      hypervisor = "qemu";

      vcpu = 4;
      mem = 16384;

      volumes = [
        {
          image = "behemoth-tailscale.img";
          mountPoint = "/var/lib/tailscale";
          size = 128;
        }
        {
          image = "behemoth-docker.img";
          mountPoint = "/var/lib/docker";
          size = 153600;
        }
      ];

      interfaces = [
        {
          type = "tap";
          id = "vm-behemoth";
          mac = "02:00:00:00:00:02";
        }
      ];
    };

    networking.hostName = "behemoth";
    services.openssh = {
      enable = true;

      settings.PasswordAuthentication = true;
    };

    users.users.test = {
      isNormalUser = true;

      password = "password";

      extraGroups = [ "wheel" "docker" ];
    };
  };
}
