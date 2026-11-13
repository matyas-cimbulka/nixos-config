{
  flake.modules.nixos.loki =
    { config, lib, ... }:
    let
      cfg = config.deployment.loki;
      stateDir = config.services.loki.dataDir;
    in
    {
      options.deployment.loki = {
        interfaces = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = throw "Set deployment.loki.interfaces explicitly; use [] for no interface openings.";
          description = "Interfaces permitted to reach Loki HTTP ingestion and queries.";
        };
      };
      config = lib.mkMerge [
        { services.loki.enable = lib.mkDefault true; }
        (lib.mkIf config.services.loki.enable {
          networking.firewall.interfaces = lib.genAttrs cfg.interfaces (_: {
            allowedTCPPorts = [ config.services.loki.configuration.server.http_listen_port ];
          });

          systemd.services.loki.serviceConfig = {
            StateDirectory = "loki";
            StateDirectoryMode = "0750";
          };

          services.loki = {
            dataDir = lib.mkDefault "/var/lib/loki";

            configuration = {
              auth_enabled = false;

              server = {
                http_listen_address = lib.mkDefault "0.0.0.0";
                http_listen_port = lib.mkDefault 3100;
                grpc_listen_address = "127.0.0.1";
              };

              common = {
                instance_addr = "127.0.0.1";
                path_prefix = stateDir;
                replication_factor = 1;

                ring.kvstore.store = "inmemory";

                storage.filesystem = {
                  chunks_directory = "${stateDir}/chunks";
                  rules_directory = "${stateDir}/rules";
                };
              };

              schema_config.configs = [
                {
                  from = "2024-04-01";
                  store = "tsdb";
                  object_store = "filesystem";
                  schema = "v13";

                  index = {
                    prefix = "index_";
                    period = "24h";
                  };
                }
              ];

              storage_config.tsdb_shipper = {
                active_index_directory = "${stateDir}/index";
                cache_location = "${stateDir}/index-cache";
              };

              compactor = {
                working_directory = "${stateDir}/compactor";
                retention_enabled = true;
                delete_request_store = "filesystem";
              };

              limits_config.retention_period = "168h";
            };
          };
        })
      ];
    };
}
