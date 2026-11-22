{
  flake.modules.nixos.prometheus =
    { config, lib, ... }:
    let
      cfg = config.deployment.prometheus;
      address = config.services.prometheus.listenAddress;
      host =
        if address == "::" then
          "::1"
        else if
          builtins.elem address [ "" "0.0.0.0" ]
        then
          "127.0.0.1"
        else
          address;
      selfHost = if lib.hasInfix ":" host then "[${host}]" else host;
      systemTarget = machine: address: {
        targets = [ address ];
        labels.machine = machine;
      };
      systemTargets =
        lib.optional (config.services.alloy.enable && !cfg.overrideAlloyIntegration)
          (systemTarget config.networking.hostName "127.0.0.1:${toString (config.deployment.alloy.httpPort or 12345)}")
        ++ lib.mapAttrsToList systemTarget cfg.systemTargets;
    in
    {
      options.deployment.prometheus = {
        interfaces = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = throw "Set deployment.prometheus.interfaces explicitly; use [] for no interface openings.";
          description = "Interfaces permitted to reach the Prometheus API.";
        };
        systemTargets = lib.mkOption {
          type = lib.types.attrsOf lib.types.nonEmptyStr;
          default = { };
          description = "Remote Alloy Unix-exporter endpoints (host:port), keyed by machine name.";
        };
        overrideAlloyIntegration = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Disable scraping the local Alloy Unix exporter.";
        };
      };
      config = lib.mkMerge [
        { services.prometheus.enable = lib.mkDefault true; }
        (lib.mkIf config.services.prometheus.enable {
          networking.firewall.interfaces = lib.genAttrs cfg.interfaces (_: {
            allowedTCPPorts = [ config.services.prometheus.port ];
          });
          services.prometheus = {
            listenAddress = lib.mkDefault "0.0.0.0";
            port = lib.mkDefault 9090;
            stateDir = lib.mkDefault "prometheus2";
            retentionTime = lib.mkDefault "15d";
            extraFlags = [ "--storage.tsdb.retention.size=25GB" ];
            globalConfig.scrape_interval = lib.mkDefault "30s";
            scrapeConfigs = [
              {
                job_name = "prometheus";
                static_configs = [ { targets = [ "${selfHost}:${toString config.services.prometheus.port}" ]; } ];
              }
            ]
            ++ lib.optional (systemTargets != [ ]) {
              job_name = "system";
              metrics_path = "/api/v0/component/prometheus.exporter.unix.system/metrics";
              static_configs = systemTargets;
            };
          };
        })
      ];
    };
}
