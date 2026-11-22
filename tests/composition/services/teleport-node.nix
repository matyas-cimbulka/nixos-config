{ config, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem check;
  node = (mkSystem [ config.flake.modules.nixos.teleport-node ] {
    networking.hostName = "pilot";
    deployment.teleport-node = {
      proxyServer = "teleport.example.invalid:443";
      joinTokenFile = "/run/pilot-join-token";
      labels.access = "pilot";
    };
  }).config;
  settings = node.services.teleport.settings;
in
{
  flake.lib.compositionTests.teleport-node.reverse-tunnel-only = check "The native Teleport node should use an outbound proxy connection and a runtime enrollment token."
    (node.services.teleport.enable && settings.ssh_service.enabled
      && !settings.auth_service.enabled && !settings.proxy_service.enabled
      && settings.teleport.proxy_server == "teleport.example.invalid:443"
      && settings.teleport.nodename == "pilot" && settings.ssh_service.labels.access == "pilot"
      && settings.teleport.join_params == { method = "token"; token_name = "/run/pilot-join-token"; }
      && node.networking.firewall.allowedTCPPorts == []);
}
