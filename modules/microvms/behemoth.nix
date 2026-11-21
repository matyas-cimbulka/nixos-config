{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos.behemoth = { config, ... }:
    let
      lanInterface = config.deployment.microvm.interfaceName;
    in
    {
      imports = [
        flakeConfig.flake.modules.nixos.server-profile
        flakeConfig.flake.modules.nixos.microvm-guest

        flakeConfig.flake.modules.nixos.tailscale-microvm
        flakeConfig.flake.modules.nixos.docker
        flakeConfig.flake.modules.nixos.docker-proxy

        flakeConfig.flake.modules.nixos.traefik
        flakeConfig.flake.modules.nixos.pocket-id
        flakeConfig.flake.modules.nixos.teleport-control-plane
      ];

      deployment =
        let
          proxySubnet = "172.18.0.0/16";
        in
        {
          microvm.interfaceName = "lan0";
          tailscale = {
            interfaces = [ lanInterface ];
            metricsInterfaces = [ lanInterface ];
          };
          cadvisor.metricsInterface = lanInterface;

          docker-proxy = {
            subnet = proxySubnet;
            gateway = "172.18.0.1";
          };

          alloy = {
            httpInterfaces = [ lanInterface ];
            lokiEndpoint = "http://thoth.internal.cimbulka.net:3100/loki/api/v1/push";
            tempoEndpoint = "thoth.internal.cimbulka.net:4317";
          };

          pocket-id = {
            domain = "id.cimbulka.net";
            metricsInterfaces = [ lanInterface ];
            trustedProxies = [ proxySubnet ];
            dataVolume = "pocket-id-data";
            smtp = {
              host = "smtp.purelymail.com";
              port = 587;
              from = "id@cimbulka.net";
              user = "id@cimbulka.net";
              tls = "starttls";
            };
          };

          teleport-control-plane = {
            domain = "teleport.cimbulka.net";
            dataVolume = "teleport-data";
          };

          traefik = {
            portsByInterface = {
              ${lanInterface} = [ 80 443 8080 ];
              tailscale0 = [ 80 443 8080 ];
            };
            dnsServer = "10.77.0.1";
            acmeEmail = "matyas.cimbulka@gmail.com";

            dynamicConfig = {
              http = {
                routers.grafana = {
                  rule = "Host(`grafana.cimbulka.net`)";
                  entryPoints = [ "websecure" ];
                  service = "grafana";

                  tls.certResolver = "letsencrypt";
                };

                services.grafana.loadBalancer.servers = [
                  {
                    url = "http://thoth.internal.cimbulka.net:3000";
                  }
                ];
              };
            };
          };
        };

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
      systemd.network.networks.lan.domains = [ "~internal.cimbulka.net" ];

      system.stateVersion = "26.05";
    };
}
