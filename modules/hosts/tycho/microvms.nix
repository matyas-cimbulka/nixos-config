{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos.tycho-microvms = { config, ... }:
  {
    sops.secrets.tailscale-vm-oauth = { };
    sops.secrets.cloudflare-dns-api-token = { };
    sops.secrets.pocket-id-encryption-key = { };
    sops.secrets.pocket-id-smtp-password = { };

    sops.templates."cloudflare-dns.env" = {
      mode = "0400";

      content = ''
        CF_DNS_API_TOKEN=${config.sops.placeholder.cloudflare-dns-api-token}
      '';
    };

    sops.templates."pocket-id.env" = {
      mode = "0400";

      content = ''
        ENCRYPTION_KEY=${config.sops.placeholder.pocket-id-encryption-key}
        SMTP_PASSWORD=${config.sops.placeholder.pocket-id-smtp-password}
      '';
    };

    microvm.vms = {
      anderson.config = {
        imports = [ flakeConfig.flake.modules.nixos.anderson ];

        microvm.credentialFiles.tailscale-vm-oauth =
          "/run/credentials/microvm@anderson.service/tailscale-vm-oauth";
      };

      test-microvm.config.imports = [ flakeConfig.flake.modules.nixos.test-microvm ];
      
      behemoth.config = {
        imports = [ flakeConfig.flake.modules.nixos.behemoth ];

        microvm.credentialFiles = {
          tailscale-vm-oauth = "/run/credentials/microvm@behemoth.service/tailscale-vm-oauth";
          "cloudflare-dns.env" = "/run/credentials/microvm@behemoth.service/cloudflare-dns.env";
          "pocket-id.env" = "/run/credentials/microvm@behemoth.service/pocket-id.env";
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

        serviceConfig.LoadCredential = [
          "tailscale-vm-oauth:${config.sops.secrets.tailscale-vm-oauth.path}"
        ];
      };

      "microvm@behemoth" = {
        requires = [ "sops-install-secrets.service" ];
        after = [ "sops-install-secrets.service" ];

        serviceConfig.LoadCredential = [
          "tailscale-vm-oauth:${config.sops.secrets.tailscale-vm-oauth.path}"
          "cloudflare-dns.env:${config.sops.templates."cloudflare-dns.env".path}"
          "pocket-id.env:${config.sops.templates."pocket-id.env".path}"
        ];
      };
    };
  };
}