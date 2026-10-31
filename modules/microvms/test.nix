{ config, ... }:
{
  flake.modules.nixos.test-microvm = {
    imports = [
      config.flake.modules.nixos.microvm-profile
    ];

    microvm = {
      hypervisor = "cloud-hypervisor";

      interfaces = [
        {
          type = "tap";
          id = "vm-test";
          mac = "02:68:d1:d2:1a:6a";
        }
      ];
    };

    networking.hostName = "vm-test";

    services.openssh = {
      enable = true;

      settings.PasswordAuthentication = true;
    };

    users.users.test = {
      isNormalUser = true;

      password = "password";
    };
  };
}
