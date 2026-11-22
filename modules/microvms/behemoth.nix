{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos.behemoth = { config, lib, ... }:
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
        flakeConfig.flake.modules.nixos.element-web
        flakeConfig.flake.modules.nixos.synapse
        flakeConfig.flake.modules.nixos.mas
        flakeConfig.flake.modules.nixos.pocket-id
        flakeConfig.flake.modules.nixos.teleport-control-plane
        flakeConfig.flake.modules.nixos.teleport-node
        flakeConfig.flake.modules.nixos.teleport-enrollment
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

          element-web = {
            domain = "element.cimbulka.net";
            homeserverDomain = config.deployment.synapse.domain;
            discoveryDomain = config.deployment.synapse.serverName;
          };

          synapse = {
            domain = "matrix.cimbulka.net";
            serverName = "cimbulka.net";
            dataDirectory = "/var/lib/matrix-synapse";
            databaseDirectory = "/var/lib/matrix-postgres-mas";
            mas = {
              endpoint = "http://mas:8080";
              secretFile = "/run/matrix-authentication/synapse-secret";
              secretService = "mas-state.service";
            };
          };

          mas = {
            domain = "mas.cimbulka.net";
            serverName = config.deployment.synapse.serverName;
            dataDirectory = "/var/lib/matrix-authentication";
            providerId = "01M82BRDFNG4EK61TR5Y0W3NHQ";
            homeserverDomain = config.deployment.synapse.domain;
            issuer = "https://${config.deployment.pocket-id.domain}";
            clientId = "9ffb1fd9-45a4-4477-91a9-f9de91112023";
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

          teleport-node = {
            proxyServer = "${config.deployment.teleport-control-plane.domain}:443";
            labels.type = "vm";
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

      # Local containers reach Pocket ID through Traefik without hairpinning via Tailscale.
      virtualisation.oci-containers.containers.traefik.extraOptions =
        lib.optional (!config.deployment.pocket-id.overrideTraefikIntegration)
          "--network-alias=${config.deployment.pocket-id.domain}";

      microvm = {
        hypervisor = "qemu";

        vcpu = 4;
        mem = 16384;

        volumes = lib.optional config.services.teleport.enable {
          image = "behemoth-teleport-node.img";
          mountPoint = "/var/lib/teleport";
          size = 512;
        } ++ [
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
          {
            image = "behemoth-matrix-synapse.img";
            mountPoint = config.deployment.synapse.dataDirectory;
            size = 10240;
          }
          {
            image = "behemoth-matrix-postgres.img";
            mountPoint = "/var/lib/matrix-postgres";
            size = 10240;
          }
          {
            image = "behemoth-matrix-postgres-mas.img";
            mountPoint = config.deployment.synapse.databaseDirectory;
            size = 10240;
          }
          {
            image = "behemoth-mas.img";
            mountPoint = config.deployment.mas.dataDirectory;
            size = 2048;
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
