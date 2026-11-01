{
  flake.modules.nixos.tempo = { lib, ... }: {
    networking.firewall.interfaces."lan0".allowedTCPPorts = [
      3200
      4317
    ];

    users = {
      groups.tempo = {};

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
      enable = true;

      settings = {
        target = "all";
        stream_over_http_enabled = true;

        server = {
          http_listen_address = "0.0.0.0";
          http_listen_port = 3200;

          grpc_listen_address = "127.0.0.1";
          grpc_listen_port = 9096;
        };

        distributor.receivers.otlp.protocols.grpc = {
          endpoint = "0.0.0.0:4317";
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
  };
}