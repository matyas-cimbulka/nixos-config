{ inputs, config, ... }:
{
  flake.homeConfigurations.matyas-server = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };

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
