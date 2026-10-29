{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos.tycho-microvms = { config, ... }:
  {
    sops.secrets.tailscale-vm-oauth = { };

    microvm.vms = {
      anderson.config = {
        imports = [ flakeConfig.flake.modules.nixos.anderson ];

        microvm.credentialFiles.tailscale-vm-oauth =
          "/run/credentials/microvm@anderson.service/tailscale-vm-oauth";
      };

      test-microvm.config.imports = [ flakeConfig.flake.modules.nixos.test-microvm ];
      
      behemoth.config = {
        imports = [ flakeConfig.flake.modules.nixos.behemoth ];

        microvm.credentialFiles.tailscale-vm-oauth =
          "/run/credentials/microvm@behemoth.service/tailscale-vm-oauth";
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
        ];
      };
    };
  };
}