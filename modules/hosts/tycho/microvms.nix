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
      hasKey = name: (publicKeys.${name} or null) != null;
      enroll = name: hasKey name && machines.${name}.services.teleport.enable;
      tokenName = name: "${name}-node";
      secretName = name: "${name}-teleport-enrollment-key";
      credential = name: "teleport-join-key:${config.sops.secrets.${secretName name}.path}";
      privateKeyFile = "/run/credentials/teleport.service/teleport-join-key";
      teleportDomain = machines.behemoth.deployment.teleport-control-plane.domain;
      proxyServer = "${teleportDomain}:443";
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
          roles = [ "Node" ];
          join_method = "bound_keypair";
          bound_keypair = {
            onboarding.initial_public_key = publicKeys.${name};
            recovery.mode = "insecure";
          };
        };
      }) (builtins.attrNames machines);
    in
    {
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
          grafana-secret-key = { };
          grafana-oidc-client-secret = { };
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
            }] ++ tokens;
          };

          services.tailscale.authKeyFile = "/run/credentials/tailscaled-autoconnect.service/tailscale-vm-oauth";

          systemd.services = {
            tailscaled-autoconnect = lib.mkIf config.services.tailscale.enable {
              serviceConfig.ImportCredential = [ "tailscale-vm-oauth" ];
            };
            docker-pocket-id.serviceConfig.ImportCredential = [ "pocket-id.env" ];
            docker-traefik.serviceConfig.ImportCredential = [ "cloudflare-dns.env" ];
          };

          microvm.credentialFiles = {
            tailscale-vm-oauth = "/run/credentials/microvm@behemoth.service/tailscale-vm-oauth";
            "cloudflare-dns.env" = "/run/credentials/microvm@behemoth.service/cloudflare-dns.env";
            "pocket-id.env" = "/run/credentials/microvm@behemoth.service/pocket-id.env";
          };
        };

        thoth.config = { config, lib, ... }: {
          imports = [ flakeConfig.flake.modules.nixos.thoth (vmEnrollment "thoth") ];
          deployment.teleport-node.proxyServer = proxyServer;

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
          ] ++ lib.optional (enroll "behemoth") (credential "behemoth");
        };

        "microvm@thoth" = {
          requires = [ "sops-install-secrets.service" ];
          after = [ "sops-install-secrets.service" ];

          serviceConfig.LoadCredential = [
            "grafana-secret-key:${config.sops.secrets.grafana-secret-key.path}"
            "grafana-oidc-client-secret:${config.sops.secrets.grafana-oidc-client-secret.path}"
          ] ++ lib.optional (enroll "thoth") (credential "thoth");
        };
      };
      };
    };
}
