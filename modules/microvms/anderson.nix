{ config, ... }:
{
  # Internal DNS and DHCP server
  flake.modules.nixos.anderson = {
    imports = [
      config.flake.modules.nixos.microvm-profile
    ];

    microvm = {
      hypervisor = "cloud-hypervisor";

      vcpu = 1;
      mem = 256;

      volumes = [
        {
          image = "dnsmasq.img";
          mountPoint = "/var/lib/dnsmasq";
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
  };
}