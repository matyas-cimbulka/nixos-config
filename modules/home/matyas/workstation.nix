{ inputs, config, ... }:
{
  flake.homeConfigurations.matyas-workstation = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;

    modules = [
      config.flake.modules.homeManager.matyas-workstation
    ];
  };

  flake.modules.homeManager.matyas-workstation = {
    imports = [
      config.flake.modules.homeManager.matyas-base
      config.flake.modules.homeManager.matyas-desktop-hyprland
      config.flake.modules.homeManager.matyas-desktop-ghostty
      config.flake.modules.homeManager.matyas-desktop-noctalia
    ];
  };
}
