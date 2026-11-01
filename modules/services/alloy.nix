{
  flake.modules.nixos.alloy = {
    services.alloy = {
      enable = true;

      extraFlags = [
        "--server.http.listen-addr=0.0.0.0:12345"
      ];
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

      "alloy/logs.alloy".text = ''
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
          forward_to = [ loki.write.thoth.receiver ]
        }

        loki.write "thoth" {
          endpoint {
            url = "http://thoth.internal.cimbulka.net:3100/loki/api/v1/push"
          }
        }
      '';
    };
  };
}