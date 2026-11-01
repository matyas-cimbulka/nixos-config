{
  flake.modules.nixos.alloy = {
    services.alloy = {
      enable = true;

      extraFlags = [
        "--server.http.listen-addr=0.0.0.0:12345"
      ];
    };

    environment.etc."alloy/config.alloy".text = ''
      logging {
        level = "info"
      }

      prometheus.exporter.unix "system" {
        enable_collectors = [ "systemd" ]
      }
    '';
  };
}