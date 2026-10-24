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
