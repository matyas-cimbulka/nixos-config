{
  flake.modules.nixos.prometheus = {
    services.prometheus = {
      enable = true;

      listenAddress = "0.0.0.0";
      port = 9090;

      stateDir = "prometheus2";
      retentionTime = "15d";

      extraFlags = [
        "--storage.tsdb.retention.size=25GB"
      ];

      globalConfig.scrape_interval = "30s";

      scrapeConfigs = [
        {
          job_name = "system";
          metrics_path = "/api/v0/component/prometheus.exporter.unix.system/metrics";

          static_configs = [
            {
              targets = [
                "127.0.0.1:12345"
                "10.77.0.1:12345"

                "anderson.internal.cimbulka.net:12345"
                "behemoth.internal.cimbulka.net:12345"
              ];
            }
          ];
        }
        {
          job_name = "docker";
          metrics_path = "/api/v0/component/prometheus.exporter.cadvisor.docker/metrics";

          static_configs = [
            {
              targets = [
                "behemoth.internal.cimbulka.net:12345"
              ];
            }
          ];
        }
        {
          job_name = "traefik";

          static_configs = [
            {
              targets = [
                "behemoth.internal.cimbulka.net:8080"
              ];
            }
          ];
        }
        {
          job_name = "prometheus";

          static_configs = [
            {
              targets = [
                "127.0.0.1:9090"
              ];
            }
          ];
        }
      ];
    };
  };
}