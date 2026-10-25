{ config, ... }:
{
  flake.modules.homeManager.matyas-cli-starship = {
    programs.starship = {
      enable = true;
      enableFishIntegration = true;
      enableTransience = true;

      presets = [ "no-nerd-font" ];
    };
  };

  flake.modules.homeManager.matyas-base.imports = [
    config.flake.modules.homeManager.matyas-cli-starship
  ];
}