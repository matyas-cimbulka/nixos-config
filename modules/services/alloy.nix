{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos.alloy =
    { config, lib, ... }:
    let
      cfg = config.deployment.alloy;
      containers = config.virtualisation.oci-containers.containers;
      traefikTracingEnabled =
        builtins.hasAttr "traefik" containers
        && !(config.deployment.traefik.overrideAlloyIntegration or false);
      pocketIdTracingEnabled =
        builtins.hasAttr "pocket-id" containers
        && !(config.deployment.pocket-id.overrideAlloyIntegration or false);
    in
    {
      imports = [
        flakeConfig.flake.modules.nixos.cadvisor
      ];

      options.deployment.alloy = {
        httpInterfaces = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "Interfaces permitted to access Alloy's HTTP API and exporter metrics.";
        };
        httpPort = lib.mkOption {
          type = lib.types.port;
          default = 12345;
          description = "Alloy HTTP API and exporter metrics port.";
        };
        overrideLokiIntegration = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Disable journal forwarding to Loki.";
        };
        lokiEndpoint = lib.mkOption {
          type = lib.types.str;
          description = "Loki HTTP push endpoint for journal logs.";
        };
        tempoEndpoint = lib.mkOption {
          type = lib.types.str;
          description = "Tempo OTLP gRPC endpoint.";
        };
      };

      config = lib.mkMerge [
        {
          services.alloy.enable = lib.mkDefault true;

          deployment.cadvisor.overrideIntegration = lib.mkDefault (
            !(config.services.alloy.enable && config.virtualisation.docker.enable)
          );
        }

        (lib.mkIf config.services.alloy.enable {
          networking.firewall.interfaces = lib.genAttrs cfg.httpInterfaces (_: {
            allowedTCPPorts = [ cfg.httpPort ];
          });
          services.alloy = {
            extraFlags = [ "--server.http.listen-addr=0.0.0.0:${toString cfg.httpPort}" ];
          };

          environment.etc = {
            "alloy/config.alloy".text = ''
              logging {
                level = "info"
              }

              prometheus.exporter.unix "system" {
                enable_collectors = [ "systemd" ]
              }
            '';

            "alloy/logs.alloy" = lib.mkIf (!cfg.overrideLokiIntegration) {
              text = ''
                loki.relabel "journal" {
                  forward_to = []

                  rule {
                    source_labels = [ "__journal__systemd_unit" ]
                    target_label = "unit"
                  }

                  rule {
                    source_labels = [ "__journal_container_name" ]
                    target_label = "container"
                  }
                }

                loki.source.journal "system" {
                  labels = {
                    host = constants.hostname,
                    source = "journal",
                  }

                  relabel_rules = loki.relabel.journal.rules
                  forward_to = [ loki.write.remote.receiver ]
                }

                loki.write "remote" {
                  endpoint {
                    url = ${builtins.toJSON cfg.lokiEndpoint}
                  }
                }
              '';
            };
          };
        })

        (lib.mkIf (config.services.alloy.enable && (traefikTracingEnabled || pocketIdTracingEnabled)) {
          assertions = [
            {
              assertion = config.systemd.services.docker-network-proxy.enable or false;
              message = "Alloy's Docker trace receiver requires the docker-proxy network feature.";
            }
          ];
          networking.firewall.interfaces."docker-proxy".allowedTCPPorts = [ 4318 ];

          systemd.services.alloy = {
            requires = [ "docker-network-proxy.service" ];
            after = [ "docker-network-proxy.service" ];
          };

          environment.etc."alloy/traces.alloy".text = ''
            otelcol.receiver.otlp "docker" {
              http {
                endpoint = "${config.deployment.docker-proxy.gateway}:4318"
              }

              output {
                traces = [ otelcol.processor.batch.traces.input ]
              }
            }

            otelcol.processor.batch "traces" {
              output {
                traces = [ otelcol.exporter.otlp.tempo.input ]
              }
            }

            otelcol.exporter.otlp "tempo" {
              client {
                endpoint = ${builtins.toJSON config.deployment.alloy.tempoEndpoint}

                tls {
                  insecure = true
                }
              }
            }
          '';
        })
      ];
    };
}
