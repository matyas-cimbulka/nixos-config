{ config, ... }:
{
  # Internal DNS and DHCP server
  flake.modules.nixos.anderson = {
    imports = [
      config.flake.modules.nixos.microvm-profile
      config.flake.modules.nixos.internal-dns
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

    systemd.network = {
      enable = true;

      networks.lan = {
        networkConfig = {
          Address = [ "10.77.0.2/24" ];
          Gateway = "10.77.0.1";
          DNS = [ "1.1.1.1" "1.0.0.1" ];
          DHCP = "no";
        };
      };
    };
  };
}