{
  flake.modules.nixos.teleport-node = { config, lib, ... }:
    let
      cfg = config.deployment.teleport-node;
    in
    {
      options.deployment.teleport-node = {
        proxyServer = lib.mkOption {
          type = lib.types.str;
          description = "Teleport proxy hostname and port for the outbound reverse tunnel.";
        };
        joinTokenFile = lib.mkOption {
          type = lib.types.nullOr (lib.types.strMatching "/run/.+");
          default = null;
          description = "Runtime file for a manually supplied node token. Leave unset when enrollment is managed separately.";
        };
        labels = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          description = "Node labels used by cluster access roles.";
        };
      };

      config = lib.mkMerge [ {
        services.teleport.enable = lib.mkDefault true;
      } (lib.mkIf config.services.teleport.enable {
        services.teleport.settings = {
          version = "v3";
          teleport = {
            nodename = config.networking.hostName;
            data_dir = "/var/lib/teleport";
            proxy_server = cfg.proxyServer;
          } // lib.optionalAttrs (cfg.joinTokenFile != null) {
            join_params = { method = "token"; token_name = cfg.joinTokenFile; };
          };
          auth_service.enabled = false;
          proxy_service.enabled = false;
          ssh_service = {
            enabled = true;
            labels = cfg.labels;
          };
        };
        systemd.services.teleport = {
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          unitConfig.RequiresMountsFor = [ "/var/lib/teleport" ];
          serviceConfig.StateDirectory = "teleport";
        };
      }) ];
    };
}
