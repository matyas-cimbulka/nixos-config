{ config, ... }:
{
  flake.modules.homeManager.matyas-cli-eza = {
    programs.eza = {
      enable = true;
      enableFishIntegration = true;

      colors = "auto";
      git = true;
      icons = "auto";
    };
  };

  flake.modules.homeManager.matyas-base.imports = [
    config.flake.modules.homeManager.matyas-cli-eza
  ];
}
