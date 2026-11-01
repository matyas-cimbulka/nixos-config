{
  flake.modules.nixos.grafana = {
    networking.firewall.interfaces."lan0".allowedTCPPorts = [ 3000 ];

    systemd.services.grafana.serviceConfig = {
      StateDirectory = "grafana";
      StateDirectoryMode = "0750";

      ImportCredential = [
        "grafana-secret-key"
        "grafana-oidc-client-secret"
      ];
    };

    services.grafana = {
      enable = true;
      dataDir = "/var/lib/grafana";

      settings = {
        server = {
          protocol = "http";
          http_addr = "0.0.0.0";
          http_port = 3000;

          domain = "grafana.cimbulka.net";
          root_url = "https://grafana.cimbulka.net";
        };

        security = {
          secret_key = "$__file{/run/credentials/grafana.service/grafana-secret-key}";

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

        "auth.generic_oauth" = {
          enabled = true;
          name = "Pocket ID";
          allow_sign_up = true;

          client_id = "2e3eef0c-40ca-451b-a466-8ebdd62d8e61";
          client_secret = "$__file{/run/credentials/grafana.service/grafana-oidc-client-secret}";

          scopes = "openid profile email groups";

          auth_url = "https://id.cimbulka.net/authorize";
          token_url = "https://id.cimbulka.net/api/oidc/token";
          api_url = "https://id.cimbulka.net/api/oidc/userinfo";

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
          jwk_set_url = "https://id.cimbulka.net/.well-known/jwks.json";
        };
      };

      provision = {
        enable = true;

        datasources.settings = {
          apiVersion = 1;

          datasources = [
            {
              name = "Prometheus";
              uid = "prometheus";
              type = "prometheus";
              access = "proxy";
              url = "http://127.0.0.1:9090";
              isDefault = true;

              jsonData.timeInterval = "30s";
            }
            {
              name = "Loki";
              uid = "loki";
              type = "loki";
              access = "proxy";
              url = "http://127.0.0.1:3100";
            }
            {
              name = "Tempo";
              uid = "tempo";
              type = "tempo";
              access = "proxy";
              url = "http://127.0.0.1:3200";
            }
          ];
        };
      };
    };
  };
}