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
      ];

      hardware.facter = {
        reportPath = ./facter.json;
        detected.dhcp.enable = false;
      };

      networking.hostName = "pella";
      time.timeZone = "Europe/Prague";

      system.stateVersion = "26.11";
    };
  };
}
