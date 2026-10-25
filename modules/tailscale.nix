{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos.tailscale = {
    services.tailscale = {
      enable = true;
      openFirewall = true;
    };
  };

  flake.modules.nixos.server-profile = { config, ... }: {
    imports = [
      flakeConfig.flake.modules.nixos.tailscale
    ];

    sops.secrets.tailscale-oauth = { };

    systemd.services.tailscaled-autoconnect = {
      after = [ "sops-install-secrets.service" ];
      requires = [ "sops-install-secrets.service" ];
    };

    services.tailscale = {
      authKeyFile = config.sops.secrets.tailscale-oauth.path;

      authKeyParameters = {
        ephemeral = false;
        preauthorized = true;
      };

      extraUpFlags = [ "--advertise-tags=tag:server" ];
    };
  };
}
