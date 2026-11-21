{ inputs, config, ... }:
{
  flake = {
    nixosConfigurations.pella = inputs.nixpkgs.lib.nixosSystem {
      modules = [ config.flake.modules.nixos.pella ];
    };

    modules.nixos.pella = {
      imports = [
        config.flake.modules.nixos.workstation-profile
        config.flake.modules.nixos.pella-disko
        config.flake.modules.nixos.ephemeral-root
        config.flake.modules.nixos.pella-storage
        config.flake.modules.nixos.tailscale
      ];

      hardware.facter = {
        reportPath = ./facter.json;
        detected.dhcp.enable = false;
      };

      networking.hostName = "pella";
      deployment.tailscale = {
        enrollment = "interactive";
        interfaces = [];
        overrideMetricsIntegration = true;
      };
      time.timeZone = "Europe/Prague";

      system.stateVersion = "26.11";
    };
  };
}
