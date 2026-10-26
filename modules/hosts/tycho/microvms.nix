{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos.tycho-microvms = { config, ... }:
  {
    sops.secrets.tailscale-vm-oauth = { };

    microvm.vms = {
      anderson.config.imports = [ flakeConfig.flake.modules.nixos.anderson ];
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