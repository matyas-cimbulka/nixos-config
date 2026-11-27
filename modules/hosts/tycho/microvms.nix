{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos.tycho-microvms =
    { config, lib, ... }:
    let
      publicKeys = config.deployment.teleportEnrollmentPublicKeys;
      machines = {
        anderson = config.microvm.vms.anderson.config.config;
        behemoth = config.microvm.vms.behemoth.config.config;
        thoth = config.microvm.vms.thoth.config.config;
        tycho = config;
      };
      grafanaMcpEnabled = machines.thoth.deployment.grafana.mcp.enable && machines.thoth.services.grafana.enable;
      grafanaMcpTools = [
        "search_dashboards" "get_dashboard_by_uid" "get_dashboard_panel_queries"
        "get_dashboard_property" "get_dashboard_summary" "list_datasources" "get_datasource"
        "query_prometheus" "list_prometheus_metric_metadata" "list_prometheus_metric_names"
        "list_prometheus_label_names" "list_prometheus_label_values"
        "query_loki_logs" "list_loki_label_names" "list_loki_label_values"
      ];
      grafanaMcpResources = lib.optionals grafanaMcpEnabled (lib.concatMap (suffix:
        let name = "grafana-mcp-${suffix}";
        in [{
          kind = "role";
          version = "v8";
          metadata = { inherit name; };
          spec.allow = {
            app_labels.access = "grafana-mcp";
            mcp.tools = grafanaMcpTools ++ lib.optional (suffix == "repo") "update_dashboard";
          };
        } {
          kind = "bot";
          version = "v1";
          metadata = { inherit name; };
          spec.roles = [ name ];
        }]
      ) [ "repo" "debug" ]);
      hookshotBot = "grafana-hookshot";
      hookshotKey = "hookshot-tbot-key";
      hookshotPublicKey = config.deployment.grafanaHookshotPublicKey;
      hookshotEnabled = hookshotPublicKey != null;
      hookshotApp = "hookshot-webhook";
      hookshotResources = lib.optionals hookshotEnabled [{
        kind = "role";
        version = "v7";
        metadata.name = hookshotBot;
        spec.allow.app_labels.access = hookshotApp;
      } {
        kind = "bot";
        version = "v1";
        metadata.name = hookshotBot;
        spec.roles = [ hookshotBot ];
      } {
        kind = "token";
        version = "v2";
        metadata.name = hookshotBot;
        spec = {
          roles = [ "Bot" ];
          bot_name = hookshotBot;
          join_method = "bound_keypair";
          bound_keypair = {
            onboarding.initial_public_key = hookshotPublicKey;
            recovery.mode = "insecure";
          };
        };
      }];
      hasKey = name: (publicKeys.${name} or null) != null;
      enroll = name: hasKey name && machines.${name}.services.teleport.enable;
      tokenName = name: "${name}-node";
      secretName = name: "${name}-teleport-enrollment-key";
      credential = name: "teleport-join-key:${config.sops.secrets.${secretName name}.path}";
      privateKeyFile = "/run/credentials/teleport.service/teleport-join-key";
      teleportDomain = machines.behemoth.deployment.teleport-control-plane.domain;
      proxyServer = "${teleportDomain}:443";
      matrixOidcCredential = "synapse-oidc-client-secret";
      vmEnrollment = name: { config, ... }: {
        services.teleport.enable = lib.mkIf (!hasKey name) false;
        deployment.teleport-enrollment = { tokenName = tokenName name; inherit privateKeyFile; };
        systemd.services.teleport = lib.mkIf (hasKey name && config.services.teleport.enable) {
          serviceConfig.ImportCredential = [ "teleport-join-key" ];
        };
        microvm.credentialFiles.teleport-join-key = lib.mkIf (hasKey name && config.services.teleport.enable)
          "/run/credentials/microvm@${name}.service/teleport-join-key";
      };
      tokens = lib.concatMap (name: lib.optional (enroll name) {
        kind = "token";
        version = "v2";
        metadata.name = tokenName name;
        spec = {
          roles = [ "Node" ] ++ lib.optional (name == "behemoth" || (name == "thoth" && grafanaMcpEnabled)) "App";
          join_method = "bound_keypair";
          bound_keypair = {
            onboarding.initial_public_key = publicKeys.${name};
            recovery.mode = "insecure";
          };
        };
      }) (builtins.attrNames machines);
    in
    {
      options.deployment.enableGrafanaMcp = lib.mkEnableOption "the Grafana MCP deployment on Thoth";
      options.deployment.grafanaHookshotPublicKey = lib.mkOption {
        type = lib.types.nullOr (lib.types.strMatching "ssh-ed25519 [A-Za-z0-9+/]+={0,2}");
        default = null;
        description = "Public bound key for Thoth's dedicated Grafana-to-Hookshot Teleport bot; null disables the tunnel.";
      };
      options.deployment.teleportEnrollmentPublicKeys = lib.mkOption {
        type = lib.types.attrsOf (lib.types.nullOr (lib.types.strMatching "ssh-ed25519 [A-Za-z0-9+/]+={0,2}"));
        default = {};
        description = "Public Teleport enrollment keys for Tycho and its guests. Missing or null keys leave the corresponding agents disabled.";
      };

      config = {
      services = {
        teleport.enable = lib.mkIf (!hasKey "tycho") false;
        dnsmasq.settings.cname = [ "${teleportDomain},behemoth.${lib.head (lib.toList config.services.dnsmasq.settings.domain)}" ];
      };
      deployment = {
        teleport-node = { inherit proxyServer; labels.type = "server"; };
        teleport-enrollment = { tokenName = tokenName "tycho"; inherit privateKeyFile; };
      };
      sops = {
        secrets = {
          tailscale-vm-oauth = { };
          cloudflare-dns-api-token = { };
          pocket-id-encryption-key = { };
          pocket-id-smtp-password = { };
          ${matrixOidcCredential} = { };
          grafana-secret-key = { };
          grafana-oidc-client-secret = { };
          grafana-mcp-token = lib.mkIf grafanaMcpEnabled { };
          ${hookshotKey} = lib.mkIf hookshotEnabled { };
        } // lib.mapAttrs' (name: _: lib.nameValuePair (secretName name) (lib.mkIf (enroll name) {})) machines;
        templates = {
          "cloudflare-dns.env" = {
            mode = "0400";
            content = ''
              CF_DNS_API_TOKEN=${config.sops.placeholder.cloudflare-dns-api-token}
            '';
          };
          "pocket-id.env" = {
            mode = "0400";
            content = ''
              ENCRYPTION_KEY=${config.sops.placeholder.pocket-id-encryption-key}
              SMTP_PASSWORD=${config.sops.placeholder.pocket-id-smtp-password}
            '';
          };
        };
      };

      microvm.vms = {
        anderson.config = { config, lib, ... }: {
          imports = [ flakeConfig.flake.modules.nixos.anderson (vmEnrollment "anderson") ];
          deployment.teleport-node.proxyServer = proxyServer;
          systemd.network.networks.lan.domains = lib.mkIf config.services.teleport.enable [ "~${teleportDomain}" ];

          services.tailscale.authKeyFile = "/run/credentials/tailscaled-autoconnect.service/tailscale-vm-oauth";

          systemd.services.tailscaled-autoconnect = lib.mkIf config.services.tailscale.enable {
            serviceConfig.ImportCredential = [ "tailscale-vm-oauth" ];
          };

          microvm.credentialFiles.tailscale-vm-oauth = "/run/credentials/microvm@anderson.service/tailscale-vm-oauth";
        };

        behemoth.config = { config, lib, ... }: {
          imports = [ flakeConfig.flake.modules.nixos.behemoth (vmEnrollment "behemoth") ];

          deployment = {
            traefik.environmentFile = "/run/credentials/docker-traefik.service/cloudflare-dns.env";
            pocket-id.environmentFile = "/run/credentials/docker-pocket-id.service/pocket-id.env";
            mas.clientSecretFile = "/run/credentials/docker-mas.service/${matrixOidcCredential}";
            teleport-control-plane.startupResources = [{
              kind = "role";
              version = "v7";
              metadata.name = "matyas-ssh";
              spec.allow = {
                logins = [ "matyas" ];
                node_labels."*" = "*";
              };
            } {
              kind = "user";
              version = "v2";
              metadata.name = "matyas";
              spec.roles = [ "editor" "auditor" "matyas-ssh" ] ++ lib.optional grafanaMcpEnabled "grafana-mcp-repo";
            }] ++ tokens ++ grafanaMcpResources ++ hookshotResources;
          };

          services.tailscale.authKeyFile = "/run/credentials/tailscaled-autoconnect.service/tailscale-vm-oauth";

          systemd.services = {
            tailscaled-autoconnect = lib.mkIf config.services.tailscale.enable {
              serviceConfig.ImportCredential = [ "tailscale-vm-oauth" ];
            };
            docker-pocket-id.serviceConfig.ImportCredential = [ "pocket-id.env" ];
            docker-traefik.serviceConfig.ImportCredential = [ "cloudflare-dns.env" ];
            docker-mas.serviceConfig.ImportCredential = [ matrixOidcCredential ];
          };

          microvm.credentialFiles = {
            tailscale-vm-oauth = "/run/credentials/microvm@behemoth.service/tailscale-vm-oauth";
            "cloudflare-dns.env" = "/run/credentials/microvm@behemoth.service/cloudflare-dns.env";
            "pocket-id.env" = "/run/credentials/microvm@behemoth.service/pocket-id.env";
            ${matrixOidcCredential} = "/run/credentials/microvm@behemoth.service/${matrixOidcCredential}";
          };
        };

        thoth.config = { config, lib, ... }: let
          unit = "grafana-hookshot-tunnel";
          settings = builtins.toFile "grafana-hookshot-tbot.json" (builtins.toJSON {
            version = "v2";
            proxy_server = proxyServer;
            onboarding = {
              join_method = "bound_keypair";
              token = hookshotBot;
              bound_keypair.static_private_key_path = "/run/credentials/${unit}.service/${hookshotKey}";
            };
            storage = { type = "directory"; path = "/var/lib/${unit}"; };
            services = [{ type = "application-tunnel"; app_name = hookshotApp; listen = "tcp://127.0.0.1:9900"; }];
          });
        in {
          imports = [ flakeConfig.flake.modules.nixos.thoth (vmEnrollment "thoth") ];
          deployment.teleport-node.proxyServer = proxyServer;

          deployment.grafana = {
            secretKeyFile = "/run/credentials/grafana.service/grafana-secret-key";
            oauthClientSecretFile = "/run/credentials/grafana.service/grafana-oidc-client-secret";
            mcp = {
              enable = machines.tycho.deployment.enableGrafanaMcp;
              tokenFile = "/run/credentials/grafana-mcp.service/grafana-mcp-token";
            };
          };

          systemd.services.grafana = lib.mkIf config.services.grafana.enable {
            serviceConfig.ImportCredential = [ "grafana-secret-key" ]
            ++ lib.optionals (!config.deployment.grafana.overrideOAuthIntegration) [ "grafana-oidc-client-secret" ];
          };

          systemd.services.grafana-mcp = lib.mkIf grafanaMcpEnabled {
            serviceConfig.ImportCredential = [ "grafana-mcp-token" ];
          };
          systemd.services.${unit} = lib.mkIf hookshotEnabled {
            description = "Teleport application tunnel for Grafana Matrix alerts";
            wantedBy = [ "multi-user.target" ];
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];
            environment.TBOT_CONFIG_FILE = toString settings;
            serviceConfig = {
              ExecStart = "${config.services.teleport.package}/bin/tbot start --config ${settings}";
              ImportCredential = [ hookshotKey ];
              StateDirectory = unit;
              StateDirectoryMode = "0700";
              Restart = "on-failure";
              RestartSec = "5s";
            };
          };
          microvm.volumes = lib.optional hookshotEnabled {
            image = "thoth-grafana-hookshot-tbot.img";
            mountPoint = "/var/lib/${unit}";
            size = 128;
          };
          microvm.credentialFiles = {
            ${hookshotKey} = lib.mkIf hookshotEnabled "/run/credentials/microvm@thoth.service/${hookshotKey}";
            grafana-mcp-token = lib.mkIf grafanaMcpEnabled "/run/credentials/microvm@thoth.service/grafana-mcp-token";
            grafana-secret-key = "/run/credentials/microvm@thoth.service/grafana-secret-key";
            grafana-oidc-client-secret = "/run/credentials/microvm@thoth.service/grafana-oidc-client-secret";
          };
        };
      };

      systemd.services = {
        teleport = lib.mkIf (enroll "tycho") {
          requires = [ "sops-install-secrets.service" ];
          after = [ "sops-install-secrets.service" ];
          serviceConfig.LoadCredential = [ (credential "tycho") ];
        };

        "microvm@" = {
          requires = [ "dnsmasq.service" ];
          after = [ "dnsmasq.service" ];
        };

        "microvm@anderson" = {
          requires = [ "sops-install-secrets.service" ];
          after = [ "sops-install-secrets.service" ];

          serviceConfig.LoadCredential = [ "tailscale-vm-oauth:${config.sops.secrets.tailscale-vm-oauth.path}" ]
            ++ lib.optional (enroll "anderson") (credential "anderson");
        };

        "microvm@behemoth" = {
          requires = [ "sops-install-secrets.service" ];
          after = [ "sops-install-secrets.service" ];

          serviceConfig.LoadCredential = [
            "tailscale-vm-oauth:${config.sops.secrets.tailscale-vm-oauth.path}"
            "cloudflare-dns.env:${config.sops.templates."cloudflare-dns.env".path}"
            "pocket-id.env:${config.sops.templates."pocket-id.env".path}"
            "${matrixOidcCredential}:${config.sops.secrets.${matrixOidcCredential}.path}"
          ] ++ lib.optional (enroll "behemoth") (credential "behemoth");
        };

        "microvm@thoth" = {
          requires = [ "sops-install-secrets.service" ];
          after = [ "sops-install-secrets.service" ];

          serviceConfig.LoadCredential = [
            "grafana-secret-key:${config.sops.secrets.grafana-secret-key.path}"
            "grafana-oidc-client-secret:${config.sops.secrets.grafana-oidc-client-secret.path}"
          ] ++ lib.optional (enroll "thoth") (credential "thoth")
            ++ lib.optional grafanaMcpEnabled "grafana-mcp-token:${config.sops.secrets.grafana-mcp-token.path}"
            ++ lib.optional hookshotEnabled "${hookshotKey}:${config.sops.secrets.${hookshotKey}.path}";
        };
      };
      };
    };
}
