{ config, lib, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos.tailscale = { config, ... }: {
    services.tailscale = {
      enable = true;
      openFirewall = true;

      authKeyParameters = {
        ephemeral = false;
        preauthorized = true;
      };
    };
  };

  flake.modules.nixos.tailscale-server = { config, ... }: {    
    imports = [
      flakeConfig.flake.modules.nixos.tailscale
    ];

    sops.secrets.tailscale-server-oauth = { };

    services.tailscale = {
      authKeyFile = config.sops.secrets.tailscale-server-oauth.path;

      extraUpFlags = [ "--advertise-tags=tag:server" ];
    };

    systemd.services.tailscaled-autoconnect = {
      after = [ "sops-install-secrets.service" ];
      requires = [ "sops-install-secrets.service" ];
    };
  };

  flake.modules.nixos.tailscale-microvm = { config, ... }: {
    imports = [
      flakeConfig.flake.modules.nixos.tailscale
    ];

    services.tailscale = {
      authKeyFile = "/run/credentials/tailscaled-autoconnect.service/tailscale-vm-oauth";

      extraUpFlags = [ "--advertise-tags=tag:vm" ];
    };

    systemd.services.tailscaled-autoconnect.serviceConfig.ImportCredential = [
      "tailscale-vm-oauth"
    ];
  };
}
