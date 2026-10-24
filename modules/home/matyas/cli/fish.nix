{ config, ... }:
{
  flake.modules.homeManager.matyas-cli-fish = {
    programs.fish = {
      enable = true;
    };
  };

  flake.modules.homeManager.matyas-base.imports = [
    config.flake.modules.homeManager.matyas-cli-fish
  ];
}
