{
  flake.modules.nixos.grafana =
    { config, lib, ... }:
    let
      cfg = config.deployment.grafana;
      oauth = config.services.grafana.settings."auth.generic_oauth";
      datasource =
        name: uid: address: port:
        let
          host =
            if address == "::" then
              "::1"
            else if
              builtins.elem address [ "" "0.0.0.0" ]
            then
              "127.0.0.1"
            else
              address;
          urlHost = if lib.hasInfix ":" host then "[${host}]" else host;
        in
        {
          inherit name uid;
          type = uid;
          access = "proxy";
          url = "http://${urlHost}:${toString port}";
        };
    in
    {
      options.deployment.grafana = {
        interfaces = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "Interfaces permitted to access Grafana HTTP.";
        };
        domain = lib.mkOption {
          type = lib.types.str;
          description = "Public HTTPS hostname of Grafana.";
        };
        overridePrometheusIntegration = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Disable provisioning the local Prometheus data source.";
        };
        overrideLokiIntegration = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Disable provisioning the local Loki data source.";
        };
        overrideTempoIntegration = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Disable provisioning the local Tempo data source.";
        };
        overrideOAuthIntegration = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Disable the Generic OAuth integration; the deployment configures any alternative login method.";
        };
        secretKeyFile = lib.mkOption {
          type = lib.types.strMatching "/.*";
          description = "Absolute runtime path to Grafana's signing key, readable by the Grafana service. The deployment supplies the file and startup ordering.";
        };

        oauthClientSecretFile = lib.mkOption {
          type = lib.types.strMatching "/.*";
          description = "Absolute runtime path to Grafana's OAuth client secret, readable by the Grafana service. The deployment supplies the file and startup ordering.";
        };
      };

      config = lib.mkMerge [
        { services.grafana.enable = lib.mkDefault true; }
        (lib.mkIf config.services.grafana.enable {
          assertions =
            map
              (key: {
                assertion =
                  cfg.overrideOAuthIntegration || (builtins.isString (oauth.${key} or null) && oauth.${key} != "");
                message = "Grafana OAuth requires services.grafana.settings.auth.generic_oauth.${key} supplied by the deployment.";
              })
              [ "client_id" "auth_url" "token_url" "api_url" "jwk_set_url" ];
          networking.firewall.interfaces = lib.genAttrs cfg.interfaces (_: {
            allowedTCPPorts = [ config.services.grafana.settings.server.http_port ];
          });

          systemd.services.grafana.serviceConfig = {
            StateDirectory = "grafana";
            StateDirectoryMode = "0750";
          };

          services.grafana = {
            dataDir = lib.mkDefault "/var/lib/grafana";

            settings = {
              server = {
                protocol = "http";
                http_addr = lib.mkDefault "0.0.0.0";
                http_port = lib.mkDefault 3000;

                domain = cfg.domain;
                root_url = lib.mkDefault "https://${cfg.domain}";
              };

              security = {
                secret_key = "$__file{${config.deployment.grafana.secretKeyFile}}";

                disable_initial_admin_creation = true;
                cookie_secure = true;
              };

              users = {
                allow_sign_up = false;
                auto_assign_org_role = "Viewer";
              };

              auth.disable_login_form = true;
              "auth.basic".enabled = false;
              "auth.anonymous".enabled = false;

              "auth.generic_oauth" = lib.mkIf (!cfg.overrideOAuthIntegration) {
                enabled = lib.mkDefault true;
                name = "Pocket ID";
                allow_sign_up = true;

                client_secret = "$__file{${cfg.oauthClientSecretFile}}";

                scopes = "openid profile email groups";

                login_attribute_path = "preferred_username";
                email_attribute_path = "email";
                name_attribute_path = "name";

                role_attribute_path = "contains(groups || `[]`, 'admin') && 'Editor' || 'Viewer'";
                role_attribute_strict = true;
                skip_org_role_sync = false;
                allow_assign_grafana_admin = false;

                use_pkce = true;
                use_refresh_token = true;

                validate_id_token = true;
              };
            };

            provision = {
              enable = lib.mkDefault true;
              datasources.settings = lib.mkIf config.services.grafana.provision.enable {
                apiVersion = 1;
                prune = true;
                datasources =
                  lib.optionals (config.services.prometheus.enable && !cfg.overridePrometheusIntegration) [
                    (
                      (datasource "Prometheus" "prometheus" config.services.prometheus.listenAddress
                        config.services.prometheus.port
                      )
                      // {
                        isDefault = true;
                        jsonData.timeInterval = config.services.prometheus.globalConfig.scrape_interval;
                      }
                    )
                  ]
                  ++ lib.optionals (config.services.loki.enable && !cfg.overrideLokiIntegration) [
                    (datasource "Loki" "loki" (config.services.loki.configuration.server.http_listen_address
                      or "0.0.0.0"
                    ) (config.services.loki.configuration.server.http_listen_port or 3100))
                  ]
                  ++ lib.optionals (config.services.tempo.enable && !cfg.overrideTempoIntegration) [
                    (datasource "Tempo" "tempo" (config.services.tempo.settings.server.http_listen_address or "0.0.0.0"
                    ) (config.services.tempo.settings.server.http_listen_port or 3200))
                  ];
              };
            };
          };
        })
      ];
    };
}
