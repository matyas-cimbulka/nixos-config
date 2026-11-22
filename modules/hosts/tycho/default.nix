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
        behemothTeleportEnrollmentPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILAg1YxMHN7nZYXHMnOIPeA6LuPCIxCAQPDcFia2OqKW";
        tailscale = {
          interfaces = [ "wan0" "microvm-br" ];
          metricsInterfaces = [ "microvm-br" ];
        };
        alloy = {
          httpInterfaces = [ "microvm-br" ];
          lokiEndpoint = "http://thoth.internal.cimbulka.net:3100/loki/api/v1/push";
        };
      };

      systemd.services.tailscaled-autoconnect = lib.mkIf config.services.tailscale.enable {
        requires = [ "sops-install-secrets.service" ];
        after = [ "sops-install-secrets.service" ];
      };

      system.stateVersion = "26.05";
    };
  };
}
