{
  flake.modules.nixos.pocket-id =
    { config, lib, ... }:
    let
      cfg = config.deployment.pocket-id;
      containers = config.virtualisation.oci-containers.containers;
      traefikIntegrationEnabled =
        builtins.hasAttr "traefik" containers && !cfg.overrideTraefikIntegration;
      alloyIntegrationEnabled = config.services.alloy.enable && !cfg.overrideAlloyIntegration;
    in
    {
      options.deployment.pocket-id = {
        overrideAlloyIntegration = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Disable Pocket ID tracing through the local Alloy service.";
        };
        overrideMetricsIntegration = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Disable the Prometheus metrics listener and its host exposure.";
        };
        metricsInterfaces = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "Incoming interfaces permitted to access Pocket ID's published metrics port.";
        };
        metricsPort = lib.mkOption {
          type = lib.types.port;
          default = 9464;
          description = "TCP port used for the Prometheus listener and host publication.";
        };
        overrideTraefikIntegration = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Disable automatic routing through the local Traefik container.";
        };
        domain = lib.mkOption {
          type = lib.types.str;
          description = "Public DNS hostname of Pocket ID, used for its HTTPS URL and proxy routing.";
        };
        trustedProxies = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "Trusted reverse-proxy addresses or CIDR ranges. An empty list trusts no proxy.";
        };
        dataVolume = lib.mkOption {
          type = lib.types.str;
          description = "Docker volume name or host directory mounted at /app/data.";
        };
        environmentFile = lib.mkOption {
          type = lib.types.strMatching "/.*";
          description = "Absolute runtime path to the Pocket ID environment file. The deployment supplies the file and startup ordering.";
        };
        smtp = {
          host = lib.mkOption {
            type = lib.types.str;
            description = "SMTP server hostname.";
          };
          port = lib.mkOption {
            type = lib.types.port;
            description = "SMTP server port.";
          };
          from = lib.mkOption {
            type = lib.types.str;
            description = "Sender email address.";
          };
          user = lib.mkOption {
            type = lib.types.str;
            description = "SMTP authentication username.";
          };
          tls = lib.mkOption {
            type = lib.types.enum [ "none" "starttls" "tls" ];
            description = "SMTP transport security mode.";
          };
        };
      };

      config = lib.mkMerge [
        {
          assertions = [
            {
              assertion = config.virtualisation.docker.enable;
              message = "The Pocket ID container requires Docker.";
            }
            {
              assertion = config.virtualisation.oci-containers.backend == "docker";
              message = "The Pocket ID container requires the Docker OCI backend.";
            }
            {
              assertion =
                !traefikIntegrationEnabled
                || (
                  builtins.elem "proxy" containers.pocket-id.networks
                  && builtins.elem "proxy" containers.traefik.networks
                );
              message = "Pocket ID's local Traefik integration requires both containers on the proxy network. Attach both to proxy or set deployment.pocket-id.overrideTraefikIntegration = true.";
            }
          ];

          virtualisation.oci-containers.containers.pocket-id = {
            image = "ghcr.io/pocket-id/pocket-id:v2.19.1";

            autoStart = true;

            volumes = [ "${cfg.dataVolume}:/app/data" ];

            environmentFiles = [ cfg.environmentFile ];

            environment = {
              APP_URL = "https://${cfg.domain}";
              TRUST_PROXY =
                if cfg.trustedProxies == [ ] then "false" else lib.concatStringsSep "," cfg.trustedProxies;

              UI_CONFIG_DISABLED = "true";
              ALLOW_USER_SIGNUPS = "disabled";
              ALLOW_INSECURE_CALLBACK_URLS = "false";

              SMTP_HOST = cfg.smtp.host;
              SMTP_PORT = toString cfg.smtp.port;
              SMTP_FROM = cfg.smtp.from;
              SMTP_USER = cfg.smtp.user;

              SMTP_TLS = cfg.smtp.tls;
              EMAIL_LOGIN_NOTIFICATION_ENABLED = "true";
              EMAIL_ONE_TIME_ACCESS_AS_ADMIN_ENABLED = "true";
              EMAIL_VERIFICATION_ENABLED = "true";

              ANALYTICS_DISABLED = "true";
              LOG_JSON = "true";
            };

            labels = lib.mkIf traefikIntegrationEnabled {
              "traefik.enable" = "true";
              "traefik.docker.network" = "proxy";

              "traefik.http.routers.pocket-id.rule" = "Host(`${cfg.domain}`)";
              "traefik.http.routers.pocket-id.entrypoints" = "websecure";
              "traefik.http.routers.pocket-id.service" = "pocket-id";
              "traefik.http.routers.pocket-id.tls.certresolver" = "letsencrypt";

              "traefik.http.services.pocket-id.loadbalancer.server.port" = "1411";
            };
          };
        }
        (lib.mkIf alloyIntegrationEnabled {
          assertions = [
            {
              assertion = builtins.elem "proxy" containers.pocket-id.networks;
              message = "Pocket ID tracing through Alloy requires the proxy network. Attach Pocket ID to proxy or set deployment.pocket-id.overrideAlloyIntegration = true.";
            }
          ];
          virtualisation.oci-containers.containers.pocket-id.environment = {
            OTEL_TRACES_EXPORTER = "otlp";
            OTEL_EXPORTER_OTLP_TRACES_PROTOCOL = "http/protobuf";
            OTEL_EXPORTER_OTLP_TRACES_ENDPOINT = "http://${config.deployment.docker-proxy.gateway}:4318/v1/traces";
          };
        })
        (lib.mkIf (!cfg.overrideMetricsIntegration) {
          assertions = [
            {
              assertion = cfg.metricsInterfaces != [ ];
              message = "Pocket ID metrics require a non-empty deployment.pocket-id.metricsInterfaces list, or set overrideMetricsIntegration = true.";
            }
            {
              assertion = config.networking.nftables.enable;
              message = "Pocket ID metrics interface restrictions require networking.nftables.enable.";
            }
          ];
          networking = {
            firewall.interfaces = lib.genAttrs cfg.metricsInterfaces (_: {
              allowedTCPPorts = [ cfg.metricsPort ];
            });
            nftables = {
              enable = lib.mkDefault true;
              tables.pocket-id-exposure = {
                family = "inet";
                content = ''
                  chain metrics {
                    type filter hook prerouting priority -110; policy accept;
                    # Restrict the host port before Docker's destination NAT.
                    fib daddr type local ct direction original tcp dport ${toString cfg.metricsPort} ${
                      lib.optionalString (cfg.metricsInterfaces != [ ]) (
                        "iifname != { " + lib.concatMapStringsSep ", " builtins.toJSON cfg.metricsInterfaces + " } "
                      )
                    }counter drop
                  }
                '';
              };
            };
          };
          virtualisation.oci-containers.containers.pocket-id = {
            ports = [ "${toString cfg.metricsPort}:${toString cfg.metricsPort}" ];
            environment = {
              OTEL_METRICS_EXPORTER = "prometheus";
              OTEL_EXPORTER_PROMETHEUS_HOST = "0.0.0.0";
              OTEL_EXPORTER_PROMETHEUS_PORT = toString cfg.metricsPort;
            };
          };
          systemd.services.${containers.pocket-id.serviceName} = {
            requires = [ "nftables.service" ];
            after = [ "nftables.service" ];
          };
        })
      ];
    };
}
