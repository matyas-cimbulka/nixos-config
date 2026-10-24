{ config, ... }:
{
  flake.modules.homeManager.matyas-cli-fzf = {
    programs.fzf = {
      enable = true;
      enableFishIntegration = true;
    };
  };

  flake.modules.homeManager.matyas-base.imports = [
    config.flake.modules.homeManager.matyas-cli-fzf
  ];
}
