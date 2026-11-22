{ config, ... }:
let
  flakeConfig = config;
in
{
  # Internal DNS and DHCP server
  flake.modules.nixos.anderson = { config, lib, ... }:
    let
      lanInterface = config.deployment.microvm.interfaceName;
    in
    {
      imports = [
        flakeConfig.flake.modules.nixos.server-profile
        flakeConfig.flake.modules.nixos.teleport-node
        flakeConfig.flake.modules.nixos.teleport-enrollment
        flakeConfig.flake.modules.nixos.microvm-guest

        flakeConfig.flake.modules.nixos.tailscale-microvm
        flakeConfig.flake.modules.nixos.tailscale-dns
      ];

      deployment = {
        teleport-node.labels.type = "vm";
        microvm.interfaceName = "lan0";
        tailscale = {
          interfaces = [ lanInterface ];
          metricsInterfaces = [ lanInterface ];
        };
        alloy = {
          httpInterfaces = [ lanInterface ];
          lokiEndpoint = "http://thoth.internal.cimbulka.net:3100/loki/api/v1/push";
        };
        tailscale-dns = {
          dnsInterfaces = [ "tailscale0" ];
          metricsInterfaces = [ lanInterface ];
          upstreams = [ "1.1.1.1" "1.0.0.1" ];
          mappings."cimbulka.net" = "100.119.128.83";
          zone = ''
            internal.cimbulka.net. 300 IN TXT "bridge-only"
          '';
        };
      };

      microvm = {
        hypervisor = "qemu";

        vcpu = 1;
        mem = 512;

        volumes = lib.optional config.services.teleport.enable {
          image = "anderson-teleport-node.img";
          mountPoint = "/var/lib/teleport";
          size = 512;
        } ++ [
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
      systemd.network.networks.lan.domains = [ "~internal.cimbulka.net" ];

      system.stateVersion = "26.05";
    };
}
