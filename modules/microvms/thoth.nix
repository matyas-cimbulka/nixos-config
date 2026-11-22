{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos.thoth = { config, lib, ... }:
    let
      lanInterface = config.deployment.microvm.interfaceName;
      mcp = config.deployment.grafana.mcp;
      mcpEnabled = mcp.enable && config.services.grafana.enable;
    in
    {
      imports = [
        flakeConfig.flake.modules.nixos.server-profile
        flakeConfig.flake.modules.nixos.teleport-node
        flakeConfig.flake.modules.nixos.teleport-enrollment
        flakeConfig.flake.modules.nixos.microvm-guest

        flakeConfig.flake.modules.nixos.prometheus
        flakeConfig.flake.modules.nixos.loki
        flakeConfig.flake.modules.nixos.tempo
        flakeConfig.flake.modules.nixos.grafana
      ];

      systemd.network.networks.lan = {
        domains = [ "~internal.cimbulka.net" ];
        networkConfig.DNSDefaultRoute = true;
      };

      deployment = {
        teleport-node.labels.type = "vm";
        microvm.interfaceName = "lan0";
        alloy = {
          httpInterfaces = [ lanInterface ];
          lokiEndpoint = "http://thoth.internal.cimbulka.net:3100/loki/api/v1/push";
        };
        grafana = {
          domain = "grafana.cimbulka.net";
          interfaces = [ lanInterface ];
        };
        loki.interfaces = [ lanInterface ];
        prometheus = {
          interfaces = [ lanInterface ];
          systemTargets = {
            tycho = "10.77.0.1:12345";
            anderson = "anderson.internal.cimbulka.net:12345";
            behemoth = "behemoth.internal.cimbulka.net:12345";
          };
        };
        tempo = {
          apiInterfaces = [ lanInterface ];
          otlpInterfaces = [ lanInterface ];
        };
      };

      assertions = lib.optional mcpEnabled {
        assertion = config.services.teleport.enable;
        message = "Thoth's Grafana MCP deployment requires an enrolled Teleport agent.";
      };

      services = {
        teleport.settings.app_service = lib.mkIf mcpEnabled {
          enabled = true;
          apps = [{
            name = "grafana-mcp";
            uri = "mcp+http://127.0.0.1:${toString mcp.port}/mcp";
            labels.access = "grafana-mcp";
          }];
        };
        grafana.settings."auth.generic_oauth" = {
          client_id = "2e3eef0c-40ca-451b-a466-8ebdd62d8e61";
          auth_url = "https://id.cimbulka.net/authorize";
          token_url = "https://id.cimbulka.net/api/oidc/token";
          api_url = "https://id.cimbulka.net/api/oidc/userinfo";
          jwk_set_url = "https://id.cimbulka.net/.well-known/jwks.json";
          role_attribute_path = "contains(groups || `[]`, 'grafan-admin') && 'Admin' || contains(groups || `[]`, 'admin') && 'Editor' || 'Viewer'";
        };
        prometheus.scrapeConfigs = [
          {
            job_name = "tailscale";
            metrics_path = "/metrics";
            static_configs = [
              {
                targets = [
                  "10.77.0.1:9250"
                  "anderson.internal.cimbulka.net:9250"
                  "behemoth.internal.cimbulka.net:9250"
                ];
              }
            ];
          }
          {
            job_name = "pocket-id";
            metrics_path = "/metrics";
            static_configs = [
              { targets = [ "behemoth.internal.cimbulka.net:9464" ]; }
            ];
          }
          {
            job_name = "docker";
            static_configs = [ { targets = [ "behemoth.internal.cimbulka.net:8081" ]; } ];
          }
          {
            job_name = "traefik";
            static_configs = [ { targets = [ "behemoth.internal.cimbulka.net:8080" ]; } ];
          }
        ];
      };

      networking.hostName = "thoth";

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

        volumes = lib.optional config.services.teleport.enable {
          image = "thoth-teleport-node.img";
          mountPoint = "/var/lib/teleport";
          size = 512;
        } ++ [
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
      system.stateVersion = "26.05";
    };
}
