{ inputs, config, ... }:
let
  flakeConfig = config;
in
{
  flake = {
    nixosConfigurations.tycho = inputs.nixpkgs.lib.nixosSystem {
      modules = [
        inputs.microvm.nixosModules.host
        config.flake.modules.nixos.tycho
      ];
    };

    modules.nixos.tycho = { config, lib, ... }: {
      imports = [
        flakeConfig.flake.modules.nixos.tycho-disko
        flakeConfig.flake.modules.nixos.tycho-network
        flakeConfig.flake.modules.nixos.tycho-microvm-bridge
        flakeConfig.flake.modules.nixos.tycho-microvms

        flakeConfig.flake.modules.nixos.server-profile
        flakeConfig.flake.modules.nixos.sops
        flakeConfig.flake.modules.nixos.tailscale-server
        flakeConfig.flake.modules.nixos.teleport-node
        flakeConfig.flake.modules.nixos.teleport-enrollment
      ];

      hardware.facter = {
        reportPath = ./facter.json;

        detected.dhcp.enable = false;
      };

      networking.hostName = "tycho";

      sops = {
        defaultSopsFile = ./sops.yaml;
        age.keyFile = "/var/lib/sops-nix/key.txt";
        secrets.tailscale-server-oauth = { };
      };

      services.tailscale.authKeyFile = config.sops.secrets.tailscale-server-oauth.path;

      deployment = {
        enableGrafanaMcp = true;
        teleportEnrollmentPublicKeys = {
          anderson = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJOEEX6iVT9Sbxc8XlFtawwW5E+jAudg153g9TgkpGZb";
          behemoth = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILAg1YxMHN7nZYXHMnOIPeA6LuPCIxCAQPDcFia2OqKW";
          thoth = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKoIgSE9ZS46l6PilXQNBOq0WLy90/PkgsTKnWJ9yYQH";
          tycho = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH0T0TgqxKSeQX6zdguVylcUQEYLkZdPNZsfddyyZB6Y";
        };
        tailscale = {
          interfaces = [ "wan0" "microvm-br" ];
          metricsInterfaces = [ "microvm-br" ];
        };
        alloy = {
          httpInterfaces = [ "microvm-br" ];
          lokiEndpoint = "http://thoth.internal.cimbulka.net:3100/loki/api/v1/push";
        };
        grafanaHookshotPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINTRrCFX2urhwxxa2l5FRR54ZMeagy+IHAH6vkXLUcYM";
      };

      systemd.services.tailscaled-autoconnect = lib.mkIf config.services.tailscale.enable {
        requires = [ "sops-install-secrets.service" ];
        after = [ "sops-install-secrets.service" ];
      };

      system.stateVersion = "26.05";
    };
  };
}
