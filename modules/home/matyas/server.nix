{ inputs, config, ... }:
{
  flake.homeConfigurations.matyas-server = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;

    modules = [
      config.flake.modules.homeManager.matyas-server
    ];
  };

  flake.modules.homeManager.matyas-server = {
    imports = [
      config.flake.modules.homeManager.matyas-base
    ];
  };
}
