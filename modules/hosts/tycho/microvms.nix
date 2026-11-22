{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos.tycho-microvms =
    { config, lib, ... }:
    let
      behemothTeleportTokenName = "behemoth-node";
      publicKey = config.deployment.behemothTeleportEnrollmentPublicKey;
      hasBehemothEnrollmentKey = publicKey != null;
      enrollBehemoth = hasBehemothEnrollmentKey && config.microvm.vms.behemoth.config.config.services.teleport.enable;
    in
    {
      options.deployment.behemothTeleportEnrollmentPublicKey = lib.mkOption {
        type = lib.types.nullOr (lib.types.strMatching "ssh-ed25519 [A-Za-z0-9+/]+={0,2}");
        default = null;
        description = "Behemoth's public enrollment key from tbot. Null leaves its native agent disabled.";
      };

      config = {
      sops = {
        secrets = {
          tailscale-vm-oauth = { };
          cloudflare-dns-api-token = { };
          pocket-id-encryption-key = { };
          pocket-id-smtp-password = { };
          grafana-secret-key = { };
          grafana-oidc-client-secret = { };
          behemoth-teleport-enrollment-key = lib.mkIf enrollBehemoth { };
        };
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
          imports = [ flakeConfig.flake.modules.nixos.anderson ];

          services.tailscale.authKeyFile = "/run/credentials/tailscaled-autoconnect.service/tailscale-vm-oauth";

          systemd.services.tailscaled-autoconnect = lib.mkIf config.services.tailscale.enable {
            serviceConfig.ImportCredential = [ "tailscale-vm-oauth" ];
          };

          microvm.credentialFiles.tailscale-vm-oauth = "/run/credentials/microvm@anderson.service/tailscale-vm-oauth";
        };

        behemoth.config = { config, lib, ... }: {
          imports = [ flakeConfig.flake.modules.nixos.behemoth ];

          deployment = {
            traefik.environmentFile = "/run/credentials/docker-traefik.service/cloudflare-dns.env";
            pocket-id.environmentFile = "/run/credentials/docker-pocket-id.service/pocket-id.env";
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
              spec.roles = [ "editor" "auditor" "matyas-ssh" ];
            }] ++ lib.optional enrollBehemoth {
              kind = "token";
              version = "v2";
              metadata.name = behemothTeleportTokenName;
              spec = {
                roles = [ "Node" ];
                join_method = "bound_keypair";
                bound_keypair = {
                  onboarding.initial_public_key = publicKey;
                  recovery.mode = "insecure";
                };
              };
            };
            teleport-enrollment = {
              tokenName = behemothTeleportTokenName;
              privateKeyFile = "/run/credentials/teleport.service/teleport-join-key";
            };
          };

          services.teleport.enable = lib.mkIf (!hasBehemothEnrollmentKey) false;
          services.tailscale.authKeyFile = "/run/credentials/tailscaled-autoconnect.service/tailscale-vm-oauth";

          systemd.services = {
            tailscaled-autoconnect = lib.mkIf config.services.tailscale.enable {
              serviceConfig.ImportCredential = [ "tailscale-vm-oauth" ];
            };
            docker-pocket-id.serviceConfig.ImportCredential = [ "pocket-id.env" ];
            docker-traefik.serviceConfig.ImportCredential = [ "cloudflare-dns.env" ];
            teleport = lib.mkIf enrollBehemoth {
              serviceConfig.ImportCredential = [ "teleport-join-key" ];
            };
          };

          microvm.credentialFiles = {
            tailscale-vm-oauth = "/run/credentials/microvm@behemoth.service/tailscale-vm-oauth";
            "cloudflare-dns.env" = "/run/credentials/microvm@behemoth.service/cloudflare-dns.env";
            "pocket-id.env" = "/run/credentials/microvm@behemoth.service/pocket-id.env";
            teleport-join-key = lib.mkIf enrollBehemoth "/run/credentials/microvm@behemoth.service/teleport-join-key";
          };
        };

        thoth.config = { config, lib, ... }: {
          imports = [ flakeConfig.flake.modules.nixos.thoth ];

          deployment.grafana = {
            secretKeyFile = "/run/credentials/grafana.service/grafana-secret-key";
            oauthClientSecretFile = "/run/credentials/grafana.service/grafana-oidc-client-secret";
          };

          systemd.services.grafana = lib.mkIf config.services.grafana.enable {
            serviceConfig.ImportCredential = [ "grafana-secret-key" ]
            ++ lib.optionals (!config.deployment.grafana.overrideOAuthIntegration) [ "grafana-oidc-client-secret" ];
          };

          microvm.credentialFiles = {
            grafana-secret-key = "/run/credentials/microvm@thoth.service/grafana-secret-key";
            grafana-oidc-client-secret = "/run/credentials/microvm@thoth.service/grafana-oidc-client-secret";
          };
        };
      };

      systemd.services = {
        "microvm@" = {
          requires = [ "dnsmasq.service" ];
          after = [ "dnsmasq.service" ];
        };

        "microvm@anderson" = {
          requires = [ "sops-install-secrets.service" ];
          after = [ "sops-install-secrets.service" ];

          serviceConfig.LoadCredential = [ "tailscale-vm-oauth:${config.sops.secrets.tailscale-vm-oauth.path}" ];
        };

        "microvm@behemoth" = {
          requires = [ "sops-install-secrets.service" ];
          after = [ "sops-install-secrets.service" ];

          serviceConfig.LoadCredential = [
            "tailscale-vm-oauth:${config.sops.secrets.tailscale-vm-oauth.path}"
            "cloudflare-dns.env:${config.sops.templates."cloudflare-dns.env".path}"
            "pocket-id.env:${config.sops.templates."pocket-id.env".path}"
          ] ++ lib.optional enrollBehemoth "teleport-join-key:${config.sops.secrets.behemoth-teleport-enrollment-key.path}";
        };

        "microvm@thoth" = {
          requires = [ "sops-install-secrets.service" ];
          after = [ "sops-install-secrets.service" ];

          serviceConfig.LoadCredential = [
            "grafana-secret-key:${config.sops.secrets.grafana-secret-key.path}"
            "grafana-oidc-client-secret:${config.sops.secrets.grafana-oidc-client-secret.path}"
          ];
        };
      };
      };
    };
}
