{
  flake.modules.nixos.tempo =
    { config, lib, ... }:
    let
      cfg = config.deployment.tempo;
    in
    {
      options.deployment.tempo = {
        apiInterfaces = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "Interfaces permitted to reach Tempo HTTP queries and metrics.";
        };
        otlpInterfaces = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "Interfaces permitted to reach Tempo OTLP gRPC ingestion.";
        };
        otlpPort = lib.mkOption {
          type = lib.types.port;
          default = 4317;
          description = "Tempo OTLP gRPC port.";
        };
      };
      config = lib.mkMerge [
        { services.tempo.enable = lib.mkDefault true; }
        (lib.mkIf config.services.tempo.enable {
          networking.firewall.interfaces = lib.mkMerge [
            (lib.genAttrs cfg.apiInterfaces (_: {
              allowedTCPPorts = [ config.services.tempo.settings.server.http_listen_port ];
            }))
            (lib.genAttrs cfg.otlpInterfaces (_: {
              allowedTCPPorts = [ cfg.otlpPort ];
            }))
          ];

          users = {
            groups.tempo = { };

            users.tempo = {
              isSystemUser = true;
              group = "tempo";
            };
          };

          systemd.services.tempo.serviceConfig = {
            DynamicUser = lib.mkForce false;
            User = "tempo";
            Group = "tempo";
            StateDirectoryMode = "0750";
          };

          services.tempo = {

            settings = {
              target = "all";
              stream_over_http_enabled = true;

              server = {
                http_listen_address = lib.mkDefault "0.0.0.0";
                http_listen_port = lib.mkDefault 3200;

                grpc_listen_address = "127.0.0.1";
                grpc_listen_port = 9096;
              };

              distributor.receivers.otlp.protocols.grpc = {
                endpoint = "0.0.0.0:${toString cfg.otlpPort}";
              };

              live_store = {
                ring = {
                  instance_addr = "127.0.0.1";
                  kvstore.store = "inmemory";
                };

                partition_ring.kvstore.store = "inmemory";

                wal.path = "/var/lib/tempo/live-store";
                shutdown_marker_dir = "/var/lib/tempo/shutdown-marker";
              };

              storage.trace = {
                backend = "local";

                wal.path = "/var/lib/tempo/wal";
                local.path = "/var/lib/tempo/blocks";
              };

              backend_scheduler.local_work_path = "/var/lib/tempo/scheduler";
              backend_worker.compaction.block_retention = "168h";
            };
          };
        })
      ];
    };
}
