{ config, ... }:
{
  flake.modules.nixos.thoth = {
    imports = [
      config.flake.modules.nixos.microvm-profile

      config.flake.modules.nixos.prometheus
    ];

    networking = {
      hostName = "thoth";

      firewall.interfaces."lan0".allowedTCPPorts = [ 9090 ];
    };

    microvm = {
      hypervisor = "qemu";

      vcpu = 2;
      mem = 4096;

      interfaces = [
        {
          type = "tap";
          id = "vm-thoth";
          mac = "02:00:00:00:00:03";
        }
      ];

      volumes = [
        {
          image = "thoth-grafana.img";
          mountPoint = "/var/lib/grafana";
          size = 1024;
        }
        {
          image = "thoth-prometheus.img";
          mountPoint = "/var/lib/prometheus2";
          size = 30720;
        }
        {
          image = "thoth-loki.img";
          mountPoint = "/var/lib/loki";
          size = 30720;
        }
        {
          image = "thoth-tempo.img";
          mountPoint = "/var/lib/tempo";
          size = 30720;
        }
      ];
    };
  };
}