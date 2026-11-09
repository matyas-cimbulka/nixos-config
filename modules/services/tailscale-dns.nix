{
  flake.modules.nixos.tailscale-dns =
    { config, lib, ... }:
    let
      cfg = config.deployment.tailscale-dns;
    in
    {
      options.deployment.tailscale-dns = {
        dnsInterfaces = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "Interfaces permitted to send DNS queries.";
        };
        dnsPort = lib.mkOption {
          type = lib.types.port;
          default = 53;
          description = "Blocky DNS port.";
        };
        metricsInterfaces = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "Interfaces permitted to reach Blocky HTTP/HTTPS metrics.";
        };
        metricsHttpPort = lib.mkOption {
          type = lib.types.port;
          default = 80;
          description = "Blocky HTTP metrics port.";
        };
        metricsHttpsPort = lib.mkOption {
          type = lib.types.port;
          default = 443;
          description = "Blocky HTTPS metrics port.";
        };
        overrideMetricsIntegration = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Disable Blocky Prometheus metrics and their listeners.";
        };
        upstreams = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "Upstream DNS servers.";
        };
        mappings = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          description = "Explicit custom DNS mappings.";
        };
        zone = lib.mkOption {
          type = lib.types.lines;
          description = "Additional custom DNS zone records.";
        };
      };
      config = lib.mkMerge [
        { services.blocky.enable = lib.mkDefault true; }
        (lib.mkIf config.services.blocky.enable {
          assertions = [
            {
              assertion = config.services.tailscale.enable;
              message = "The Tailscale DNS feature requires Tailscale.";
            }
            {
              assertion = config.services.resolved.enable;
              message = "The Tailscale DNS feature requires systemd-resolved for host DNS resolution.";
            }
          ];
          networking.firewall.interfaces = lib.genAttrs cfg.dnsInterfaces (_: {
            allowedUDPPorts = [ cfg.dnsPort ];
            allowedTCPPorts = [ cfg.dnsPort ];
          });

          environment.etc."resolv.conf".source = lib.mkForce "/run/systemd/resolve/resolv.conf";

          services = {
            tailscale.extraSetFlags = [ "--accept-dns=false" ];

            resolved = {
              enable = lib.mkDefault true;
              settings.Resolve.DNSStubListener = false;
            };

            blocky = {

              settings = {
                upstreams = {
                  init.strategy = "fast";

                  groups.default = cfg.upstreams;

                  strategy = "parallel_best";
                  timeout = "2s";
                };

                connectIPVersion = "v4";

                customDNS = {
                  customTTL = "1h";
                  filterUnmappedTypes = true;

                  mapping = cfg.mappings;

                  zone = cfg.zone;
                };

                blocking = {
                  denylists = {
                    ads = [
                      "https://s3.amazonaws.com/lists.disconnect.me/simple_ad.txt"
                      "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
                      "http://sysctl.org/cameleon/hosts"
                      "https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt"
                    ];

                    special = [
                      "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews/hosts"
                    ];
                  };

                  clientGroupsBlock = {
                    default = [ "ads" "special" ];
                  };

                  blockType = "zeroIp";
                };

                caching = {
                  minTime = "2m";
                  maxTime = "30m";

                  prefetching = true;
                  prefetchExpires = "2h";
                };

                ports.dns = cfg.dnsPort;

                fqdnOnly.enable = true;
              };
            };
          };
        })
        (lib.mkIf (config.services.blocky.enable && !cfg.overrideMetricsIntegration) {
          networking.firewall.interfaces = lib.genAttrs cfg.metricsInterfaces (_: {
            allowedTCPPorts = [
              cfg.metricsHttpPort
              cfg.metricsHttpsPort
            ];
          });
          services.blocky.settings = {
            prometheus.enable = true;
            ports = {
              http = cfg.metricsHttpPort;
              https = cfg.metricsHttpsPort;
            };
          };
        })
      ];
    };
}
