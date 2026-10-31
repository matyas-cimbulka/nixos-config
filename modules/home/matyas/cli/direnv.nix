{ config, ... }:
{
  flake.modules.homeManager.matyas-cli-direnv = {
    programs.direnv = {
      enable = true;
      enableFishIntegration = true;
    };
  };

  flake.modules.homeManager.matyas-base.imports = [
    config.flake.modules.homeManager.matyas-cli-direnv
  ];
}
