{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos = {
    tailscale =
      { config, lib, ... }:
      let
        cfg = config.deployment.tailscale;
      in
      {
        options.deployment.tailscale = {
          interfaces = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = throw "Set deployment.tailscale.interfaces explicitly; use [] for no transport interface openings.";
            description = "Incoming interfaces permitted to reach Tailscale's UDP transport port.";
          };
          metricsInterfaces = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "Interfaces permitted to reach Tailscale client metrics and the read-only status page.";
          };
          metricsPort = lib.mkOption {
            type = lib.types.port;
            default = 9250;
            description = "Port for the read-only Tailscale web listener serving /metrics.";
          };
          overrideMetricsIntegration = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Disable the Tailscale client metrics listener and its exposure.";
          };
        };
        config = lib.mkMerge [
          { services.tailscale.enable = lib.mkDefault true; }
          (lib.mkIf config.services.tailscale.enable {
            assertions = [
              {
                assertion = config.services.tailscale.authKeyFile != null;
                message = "The Tailscale feature requires services.tailscale.authKeyFile supplied by the deployment.";
              }
              {
                assertion = !config.services.tailscale.openFirewall;
                message = "The Tailscale feature opens its transport port per deployment interface; keep services.tailscale.openFirewall = false.";
              }
            ];
            networking.firewall.interfaces = lib.genAttrs config.deployment.tailscale.interfaces (_: {
              allowedUDPPorts = [ config.services.tailscale.port ];
            });
            services.tailscale = {
              openFirewall = lib.mkDefault false;
              authKeyParameters = {
                ephemeral = false;
                preauthorized = true;
              };
            };
          })
          (lib.mkIf (config.services.tailscale.enable && !cfg.overrideMetricsIntegration) {
            assertions = [
              {
                assertion = cfg.metricsInterfaces != [ ];
                message = "Tailscale metrics require a non-empty deployment.tailscale.metricsInterfaces list, or set overrideMetricsIntegration = true.";
              }
              {
                assertion = config.networking.nftables.enable;
                message = "Tailscale metrics interface restrictions require networking.nftables.enable.";
              }
            ];
            networking = {
              firewall.interfaces = lib.genAttrs cfg.metricsInterfaces (_: {
                allowedTCPPorts = [ cfg.metricsPort ];
              });
              nftables = {
                enable = lib.mkDefault true;
                tables.tailscale-metrics = {
                  family = "inet";
                  content = ''
                    chain incoming {
                      type filter hook prerouting priority -110; policy accept;
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
            systemd.services.tailscale-metrics = {
              description = "Tailscale read-only client metrics listener";
              wantedBy = [ "multi-user.target" ];
              requires = [ "tailscaled.service" "nftables.service" ];
              after = [ "tailscaled.service" "nftables.service" ];
              serviceConfig = {
                ExecStart = "${lib.getExe config.services.tailscale.package} web --readonly --listen 0.0.0.0:${toString cfg.metricsPort}";
                Restart = "on-failure";
              };
            };
          })
        ];
      };

    tailscale-server = { config, lib, ... }: {
      imports = [
        flakeConfig.flake.modules.nixos.tailscale
      ];

      config = lib.mkIf config.services.tailscale.enable {
        services.tailscale.extraUpFlags = lib.mkDefault [ "--advertise-tags=tag:server" ];
      };
    };

    tailscale-microvm = { config, lib, ... }: {
      imports = [
        flakeConfig.flake.modules.nixos.tailscale
      ];

      config =
        lib.mkIf (config.services.tailscale.enable && config.services.tailscale.authKeyFile != null)
          {
            services.tailscale.extraUpFlags = lib.mkDefault [ "--advertise-tags=tag:vm" ];
            systemd = {
              network.wait-online = {
                enable = true;
                extraArgs = [ "--ipv4" "--dns" ];
              };
              services.tailscaled-autoconnect = {
                requires = [ "systemd-resolved.service" "systemd-networkd-wait-online.service" ];
                after = [ "systemd-resolved.service" "systemd-networkd-wait-online.service" ];
              };
            };
          };
    };
  };
}
