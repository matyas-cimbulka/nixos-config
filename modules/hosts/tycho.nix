{ inputs, config, ... }:
{
  flake.nixosConfigurations.tycho = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      config.flake.modules.nixos.tycho
    ];
  };

  flake.modules.nixos.tycho = {
    imports = [
      config.flake.modules.nixos.tycho-disko
      config.flake.modules.nixos.server-profile
    ];

    hardware.facter.reportPath = ./facter.json;

    networking.hostName = "tycho";

    system.stateVersion = "26.05";
  };
}